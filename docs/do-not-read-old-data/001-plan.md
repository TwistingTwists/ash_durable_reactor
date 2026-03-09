# Durable Reactor Plan

## Core Position

This should be built as checkpointed replay, not as "serialize the halted `Reactor` struct and store it in Postgres".

Reactor can halt and resume, but its in-memory struct and executor state contain runtime details that are not a stable persistence boundary. A durable implementation should instead persist:

- run identity and lifecycle state
- step identity, inputs, outputs, attempt count, and terminal/intermediate status
- enough metadata to replay the same graph and skip already-completed work

That design is simpler, more Ash-native, and more realistic to make correct.

## What `reactor_req` And `reactor_process` Teach Us

I reviewed:

- `reactor_req`
- `reactor_process`

The useful lessons are architectural, not domain-specific.

### `reactor_req`: add capability by patching the existing `reactor` DSL

`reactor_req` is intentionally thin:

- it uses `Spark.Dsl.Extension`
- it adds entities into the existing `:reactor` section via `dsl_patches`
- each DSL entity implements `Reactor.Dsl.Build`
- builders compile DSL into ordinary Reactor steps
- one reusable step implementation (`Reactor.Req.Step`) handles the runtime work

That is a strong precedent for durable-specific DSL primitives. If we add durable-only steps later, they should compile into normal Reactor steps the same way.

Examples of useful future durable entities:

- `await_resume`
- `persist_value`
- `record_checkpoint`
- `emit_event`

These should be sugar over normal step implementations, not a second execution engine.

### `reactor_process`: inject runtime requirements automatically

`reactor_process` is the more important precedent.

It does two things that matter directly for durability:

- it injects required middleware with a transformer
- it encodes execution constraints in builders and steps, for example `async?: false`

Concretely:

- `Reactor.Process.Dsl.Transformer` adds `Reactor.Process.Middleware` automatically
- `Reactor.Process.Step.StartLink` validates that it is running in the owning process
- the builder sets `async?: false` because the runtime model requires it

That is exactly the pattern durable Reactor should follow:

- do not rely on users to remember middleware
- do not rely on users to remember execution-mode restrictions
- fail clearly when runtime invariants are violated

### Implication for this project

The original plan was directionally right, but it underspecified extension ergonomics and runtime invariants.

After reading these libraries, the durable package should be designed as:

1. a normal Reactor extension
2. with automatic middleware injection
3. with transformer-driven step wrapping
4. with explicit async/concurrency limits where correctness requires them
5. with optional durable DSL entities compiled through `Reactor.Dsl.Build`

## Revised Package Shape

The package should look more like `reactor_process` than like a standalone helper library.

```elixir
defmodule AshDurableReactor do
  use Spark.Dsl.Extension,
    sections: [AshDurableReactor.Dsl.Durable.section()],
    dsl_patches: AshDurableReactor.Dsl.Patches.entities(),
    transformers: [
      AshDurableReactor.Transformers.ValidateConfig,
      AshDurableReactor.Transformers.AddMiddleware,
      AshDurableReactor.Transformers.WrapSteps,
      AshDurableReactor.Transformers.EnforceExecutionMode
    ]

  @behaviour Ash.Extension
end
```

This should support two extension surfaces:

- a `durable do ... end` config section for reactor-wide durability policy
- optional `dsl_patches` into `:reactor` for durable-specific steps

That split follows the two observed extension styles:

- config + middleware injection from `reactor_process`
- new step entities from `reactor_req`

## Recommended User-Facing DSL

```elixir
defmodule MyApp.Reactors.ImportCustomer do
  use Reactor, extensions: [Ash.Reactor, AshDurableReactor]

  durable do
    run_resource MyApp.Durable.Run
    step_resource MyApp.Durable.Step
    event_resource MyApp.Durable.StepEvent
    codec MyApp.Durable.JsonCodec
    persist_context [:actor, :tenant, :request_id]
    resume_strategy :replay
    default_async? false
    max_concurrency 1
    durable_undo? true
    durable_compensation? true
  end

  ash do
    default_domain MyApp.Support
  end

  input :customer_id

  read_one :customer, MyApp.Support.Customer, :by_id do
    inputs %{id: input(:customer_id)}
  end

  action :sync_to_crm, MyApp.CRM.SyncStep do
    inputs %{customer: result(:customer)}
  end

  return :sync_to_crm
end
```

Important change from the original plan:

- `default_async? false` should not just be documentation
- the extension should actually enforce or rewrite execution mode where durability would otherwise become unsafe or non-deterministic

## Entry Point: Ash Actions, Not Ad Hoc Runtime Calls

Durable runs should start from Ash actions so actor, tenant, authorization context, and tracing metadata are naturally available and persistable.

That means the operational surface should be:

- start run
- resume run
- cancel run
- retry run or step
- inspect run

All as normal Ash actions on durable resources.

## Persistence Model

The original `runs + steps (+ events)` model is still correct. Keep it.

### `reactor_runs`

- `id`
- `run_id`
- `reactor_module`
- `reactor_version`
- `status`
- `inputs`
- `persisted_context`
- `result`
- `error`
- `halt_reason`
- `resume_token`
- `current_step_count`
- `started_at`
- `completed_at`
- `next_resume_at`
- `claimed_by`
- `claimed_at`
- `lock_version`

### `reactor_steps`

- `id`
- `run_id`
- `step_name`
- `step_impl`
- `step_hash`
- `status`
- `attempt`
- `inputs`
- `output`
- `error`
- `halt_payload`
- `compensation_error`
- `undo_error`
- `started_at`
- `completed_at`
- `next_retry_at`
- `worker_pid_or_node`

### `reactor_step_events` optional but recommended

- `id`
- `run_id`
- `step_name`
- `event_type`
- `payload`
- `inserted_at`

Two additions matter for long-term durability:

- `reactor_version` or `step_hash` so replay can detect code drift
- optimistic locking fields so multiple resume workers do not race

## The Most Important Runtime Rule

Middleware is necessary, but middleware alone is not enough.

`reactor_process` demonstrates where middleware fits well: injecting runtime context and enforcing invariants. Durable execution needs that too, but it also needs replay at the step boundary.

So the runtime must have both:

1. middleware for run lifecycle and shared context
2. a step wrapper that can short-circuit from persisted state

The wrapper is the real durability boundary.

## Step Wrapping Strategy

Every normal step should be rewritten to a durable delegator after the DSL has already been expanded.

Conceptually:

```elixir
%Reactor.Step{
  name: original.name,
  impl:
    {AshDurableReactor.StepWrapper,
     original_impl: original.impl,
     step_name: original.name,
     step_impl: inspect(original.impl)}
}
```

The wrapper should:

1. load persisted step state for `run_id + step_name`
2. return stored output immediately for successful replayable steps
3. return stored halt payload for resumable waiting steps
4. mark the step as running before delegating
5. delegate to the original step
6. persist normal result, halt result, retry metadata, compensation result, and undo result

This is the main place where "durable as possible" is won or lost.

## Middleware Responsibilities

Following the `reactor_process` pattern, the middleware should be auto-injected by a transformer, not manually configured by users.

It should only own run-scoped concerns:

- `init/1`: create or load run state, attach `durable_run_id`
- `halt/1`: persist halt metadata and resume information
- `complete/2`: mark the run succeeded and persist final result
- `error/2`: mark the run failed and persist final error
- `event/3`: optionally record cheap lifecycle events

Do not put expensive persistence logic into `event/3`. Reactor middleware events are on the hot path.

## Execution Constraints

This is the biggest improvement to the old plan.

`reactor_process` does not merely document constraints; it encodes them in the extension. Durable Reactor should do the same.

### v1 defaults

- default to synchronous execution
- default to one durable worker per run
- disable unrestricted async fan-out unless explicitly marked safe

### enforcement

The extension should:

- rewrite wrapped steps to `async?: false` by default
- reject incompatible reactor features in validation
- raise clear errors when a durable invariant is broken

Examples of invariants worth enforcing:

- no durable replay for anonymous non-serializable step outputs
- no replay across code-version mismatch without a policy
- no per-step async execution when a wrapper depends on in-process undo state

This is exactly the kind of opinionated guardrail `reactor_process` shows is acceptable in a Reactor extension.

## Durability Policy Per Step

To make this "as durable as possible", the plan should explicitly support per-step policies instead of a single global behavior.

Recommended policies:

- `mode: :replayable`
- `mode: :ephemeral`
- `mode: :resumable`
- `mode: :side_effect_once`

Examples:

- pure computation or Ash read steps: usually `:replayable`
- process PIDs and sockets: usually `:ephemeral`
- human approval steps: `:resumable`
- non-idempotent external mutations: `:side_effect_once` with dedupe key support

This is where durable Reactor goes beyond the original plan. The system should distinguish "cannot be re-materialized" from "can be replayed safely".

## Durable DSL Primitives

Borrowing the `reactor_req` style, v1 should keep the core runtime generic, but the extension should reserve room for a few first-class durable entities.

The most valuable ones are:

- `await_resume`
- `await_record`
- `emit_step_event`
- `checkpoint`

These should compile to normal steps through `Reactor.Dsl.Build`, not get special runtime treatment beyond the wrapper and middleware.

That keeps the model simple and consistent.

## Halt And Resume Model

The public contract should remain replay with checkpoint skipping:

- start by running the same reactor with a stable `run_id`
- resume by running the same reactor module again with the same `run_id`
- completed replayable steps return stored output
- pending or retryable steps execute
- waiting steps can unblock once external data is stored

This is cleaner than trying to reconstruct internal executor state.

## Transactions

The original warning about transaction boundaries stays and should be strengthened.

For v1:

- treat a transaction step as one durable unit
- do not persist inner transactional substeps as independently durable checkpoints
- only mark the outer transaction durable state after commit is known

Otherwise the durable log can diverge from the actual database outcome.

## Async And Dynamic Graphs

To maximize actual correctness, not theoretical feature coverage:

### v1 support

- fixed graphs
- normal Reactor steps
- Ash.Reactor-generated steps
- halt/resume
- retry/compensation/undo persistence
- JSON-friendly codecs
- scheduled resume via AshOban

### v2 or later

- dynamic step emission
- highly concurrent async graphs
- nested dynamic reactors
- exact-once effects across arbitrary external systems

This is another place where reading `reactor_process` matters: extension authors should be willing to narrow concurrency semantics to protect correctness.

## Scheduling And Recovery

AshOban should target the durable run resource, not arbitrary step execution.

The durable run record should be the source of truth for:

- resume scheduling
- stalled-run recovery
- retry timing
- operational inspection

That keeps job infrastructure subordinate to persisted workflow state.

## Implementation Order

1. Build persistence resources first: `Run`, `Step`, `StepEvent`.
2. Build a manual runtime spike with `StepWrapper` and `Middleware`.
3. Prove replay for successful steps with the same `run_id`.
4. Prove halt/resume with external input.
5. Prove retry, compensation, and undo persistence.
6. Add code-version and step-hash mismatch detection.
7. Package the runtime as a `Spark.Dsl.Extension`.
8. Add the `durable` config section.
9. Add transformer-driven middleware injection.
10. Add transformer-driven step wrapping and execution-mode enforcement.
11. Add optional durable DSL entities using `dsl_patches` plus `Reactor.Dsl.Build`.
12. Add AshOban scheduling and run recovery actions.
13. Add installer/codegen support for generated resources and formatter integration.

## Bottom-Line Recommendation

Build this as a strict Reactor extension with the ergonomics of `reactor_req` and the runtime discipline of `reactor_process`.

That means:

- checkpointed replay, not serialized executor state
- automatic middleware injection
- automatic step wrapping
- automatic execution-mode enforcement
- persisted runs as the source of truth
- optional durable DSL primitives compiled into normal steps
- per-step durability policy instead of one blanket replay mode

If the goal is "as durable as possible", the right trade is not maximum feature surface in v1. The right trade is strong invariants, explicit unsupported cases, and replay semantics that remain correct under restarts, retries, halts, and recovery workers.
