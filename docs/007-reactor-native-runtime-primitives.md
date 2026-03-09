# Reactor-Native Runtime Primitives

This document follows the Reactor-native durability direction:

- keep the normal Reactor DSL
- keep normal Reactor dependency wiring
- add durability only as a runtime layer around each step

The purpose of this note is to describe the minimum runtime and storage
primitives needed to support that design.

## Non-goals

This design does not require:

- a new agent DSL
- a new dependency language
- a run-level mutable workflow state blob
- changing how users declare `input`, `argument`, `result`, or `step`

Those remain Reactor concerns.

## The minimum durable boundary

The core durable boundary is:

- one durable run
- many durable step records inside that run

Everything else can be built on top of that.

## Primitive 1: stable run identity

Every durable execution needs a stable `run_id`.

`run_id` is the join key for:

- the run record
- all persisted step records
- resume operations
- dependency replay lookups

Without `run_id`, there is no safe way to replay or resume a workflow.

## Primitive 2: stable step identity within a run

Each step needs an identity that downstream lookups can use.

For the first version, the practical identity is:

- `run_id`
- `step_name`

That matches Reactor's own dependency model because `result(:step_name)` is how
steps refer to each other already.

If dynamic steps later need a stronger identity, we can add a derived
`step_execution_id`, but we do not need to expose that as the main public model
up front.

## Primitive 3: persisted step record

Each step execution should persist one durable record with at least:

- `run_id`
- `step_name`
- `step_impl`
- `status`
- `attempt`
- `arguments`
- `output`
- `halt_payload`
- `error`
- `inserted_at`
- `updated_at`

This is the minimum useful durable step table.

## Primitive 4: persisted resolved arguments

The runtime must persist the fully resolved argument payload that the step
actually received.

That matters because a step declaration is only the wiring. The real execution
boundary is the resolved argument map after Reactor has substituted:

- run inputs
- upstream step results
- any other resolved dependencies

So for a step like:

```elixir
step :build_message do
  argument :phase, input(:phase)
  argument :inputs, result(:extract_inputs)
  argument :week_data, result(:read_weekly_checkin)
  run AccountabilityWorkflow.Steps.BuildMessage
end
```

the persisted step record should store the resolved arguments, not just the
declaration:

```elixir
%{
  phase: "afternoon_check",
  inputs: %{project: "communication-improvement", week: "2026-W10"},
  week_data: %{goal: "ship the API draft"}
}
```

That is the durable input boundary for the step.

## Primitive 5: persisted step output

If a step succeeds, its output must be stored in its own step record.

That output becomes the replay source for downstream dependencies.

This is the key idea:

- a step persists its own output once
- downstream steps can reuse that output by looking up the upstream step record
  for the same `run_id`

This avoids requiring every step to persist a full copy of the run state.

## Primitive 6: replay lookup by dependency

The runtime needs a way to satisfy an upstream dependency from persisted step
records.

Conceptually:

- `result(:extract_inputs)` resolves to the output stored for
  `run_id + :extract_inputs`
- `result(:read_weekly_checkin)` resolves to the output stored for
  `run_id + :read_weekly_checkin`

That means persisted step outputs act as the durable source of truth for
dependency replay.

## Primitive 7: step wrapper

We need a runtime wrapper around every durable step.

That wrapper is responsible for:

1. identifying the current `run_id` and `step_name`
2. loading any existing step record
3. replaying persisted output if the step already succeeded
4. recording the resolved argument payload before or at execution time
5. executing the underlying Reactor step when needed
6. persisting the final outcome

This is the core implementation primitive. Without the step wrapper, there is no
place to enforce durable semantics consistently.

## Primitive 8: resumable halt state

Some steps halt and wait for external input.

The same step record model should support that by storing:

- `status: :halted`
- `halt_payload`
- `resume_payload` once available

Then on replay:

- if halted and not resumed, the wrapper returns the halted state
- if halted and resumed, the wrapper can continue using the persisted
  `resume_payload`

This keeps resumability inside the same per-step durable model rather than
inventing a second subsystem.

## Primitive 9: run record

The run record should stay light.

It needs enough data to anchor execution:

- `run_id`
- `reactor_module`
- `status`
- original run inputs
- persisted context
- final result
- final error

The run record should not try to duplicate all step-level execution details.
Those belong in the step records.

## Primitive 10: deterministic replay policy

The library needs a clear replay policy for previously persisted steps.

At minimum:

- if a step already succeeded, return its stored output
- if a step halted, return halted behavior until resumed
- if a step failed, either rerun or stop based on the existing Reactor failure
  path and retry semantics

The important thing is that replay policy should operate per step, not by
restoring a serialized Reactor runtime snapshot.

## What this means operationally

If the runtime has these primitives, downstream replay becomes straightforward:

1. start a run with `run_id`
2. persist each step's resolved arguments and output as it executes
3. if the run halts or crashes, restart with the same `run_id`
4. on restart, any already-succeeded dependency can be satisfied from its stored
   step output
5. only missing or incomplete steps execute again

That is the simplest form of durable execution that still remains faithful to
Reactor.

## Suggested storage contract

The library can expose this as an internal store contract:

- `put_run/1`
- `get_run/1`
- `put_step_running/1`
- `put_step_success/1`
- `put_step_halt/1`
- `put_step_error/1`
- `get_step/2`
- `list_steps/1`
- `resume_step/3`

The exact function names can change, but these are the operations the runtime
needs.

## Summary

To make durability feel native to Reactor, we do not need a new user model. We
need a precise runtime model:

- stable `run_id`
- stable step identity
- persisted resolved arguments
- persisted step outputs
- dependency replay from upstream step records
- a wrapper around step execution
- resumable halt state in the same step record model

If those primitives are correct, users can keep writing normal Reactor
workflows and get durability as an added property of step execution.
