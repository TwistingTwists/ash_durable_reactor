# Reactor-Native Durability

This note captures the stricter API direction:

- we do not invent a separate agent DSL
- we do not change how Reactor authors write workflows
- we only add one capability: any Reactor step can be made durable

The goal is to preserve the full Reactor experience and layer durability on top
of it rather than replacing Reactor's dependency model with a new one.

## Core requirement

If a user can write a workflow in normal Reactor, they should be able to write
the same workflow with durability.

That means keeping:

- `input`
- `step`
- `argument`
- `result`
- dynamic steps
- compensation
- undo
- normal Reactor dependency resolution

The durable library should only add a persistence boundary around step
execution.

## What "durable step" means

A durable step is still a normal Reactor step.

The only extra behavior is:

1. it runs under a durable `run_id`
2. its execution metadata is persisted
3. its resolved arguments are persisted
4. its output is persisted
5. on replay, previously completed dependencies can be satisfied from persisted step outputs

So the programming model stays Reactor-native. The runtime becomes
persistence-aware.

## The intended authoring model

The user should continue writing code like this:

```elixir
defmodule AccountabilityWorkflow.Reactor do
  use Reactor, extensions: [AshDurableReactor]

  durable do
    sqlite repo: MyApp.Repo
  end

  input :config
  input :phase

  step :extract_inputs, AccountabilityWorkflow.Steps.ExtractInputs do
    argument :config, input(:config)
  end

  step :read_weekly_checkin, AccountabilityWorkflow.Steps.ReadWeeklyCheckin do
    argument :config, input(:config)
    argument :inputs, result(:extract_inputs)
  end

  step :build_message, AccountabilityWorkflow.Steps.BuildMessage do
    argument :phase, input(:phase)
    argument :inputs, result(:extract_inputs)
    argument :week_data, result(:read_weekly_checkin)
  end

  step :send_message, AccountabilityWorkflow.Steps.SendMessage do
    argument :message, result(:build_message)
  end

  step :checkin_reply, AccountabilityWorkflow.Steps.CheckinReply do
    argument :delivery, result(:send_message)
  end

  step :record_checkin, AccountabilityWorkflow.Steps.RecordCheckin do
    argument :config, input(:config)
    argument :phase, input(:phase)
    argument :week_data, result(:read_weekly_checkin)
    argument :message, result(:build_message)
    argument :delivery, result(:send_message)
    argument :reply, result(:checkin_reply)
  end

  return :record_checkin
end
```

This is the right surface if the library is meant to extend Reactor instead of
abstracting it away.

## What the durable layer should do

The durable layer should sit between Reactor's planner/executor and the actual
step implementation.

For each step execution, it should persist:

- `run_id`
- `step_name`
- `step_impl`
- `step_status`
- `attempt`
- the resolved step arguments
- the step output if it succeeds
- the halt payload if it halts
- the error if it fails

In brief, the persistence contract that needs to stay tight is:

1. a stable `run_id` across every replay and resume
2. a stable step identity, at minimum `run_id + step_name`
3. persisted resolved arguments for the current step
4. persisted output, halt payload, or error for that step
5. replay lookup for upstream `result(:step_name)` from persisted step outputs

That is enough to make step replay and resumability work without changing how
the step is declared.

## The key runtime rule

Each step is responsible only for its own persisted record.

It does not need a giant snapshot of the whole workflow state.

Instead:

- every step persists its own resolved input arguments
- every step persists its own output
- if a downstream step depends on an upstream step, that dependency can be
  satisfied from the upstream step's persisted output for the same `run_id`

This keeps the persistence model local and Reactor-shaped.

## Dependency resolution model

The difficult part is not the user-facing DSL. The difficult part is runtime
resolution of step inputs during replay.

The intended resolution model is:

1. every durable run has a stable `run_id`
2. every step has a stable identity inside that run, at minimum `run_id + step_name`
3. when Reactor resolves `result(:some_step)`, the durable runtime should be
   able to satisfy that dependency from persisted storage if `:some_step` has
   already succeeded for the same `run_id`
4. when the current step executes, it persists the final resolved argument map
   that Reactor produced for it

So there are two distinct stored things:

- the persisted output of each completed step
- the persisted resolved argument payload for the current step

That gives the runtime both:

- replayable dependency outputs
- a durable audit record of what the step actually ran with

## Why this should stay step-local

A whole-run state blob is the wrong default if the goal is to stay close to
Reactor.

Reactor already defines the dependency graph. The durable layer should respect
that graph rather than flatten it into a separate state machine.

Step-local persistence is a better fit because:

- step identity is already stable in Reactor
- dependencies are already explicit through `result(:step_name)`
- replay can happen by short-circuiting individual steps
- the execution history remains understandable

## Storage shape

The storage model should remain simple and Reactor-oriented.

### Runs table

The run record needs to carry:

- `run_id`
- `reactor_module`
- `status`
- original run inputs
- final result
- final error

Its main job is to anchor the execution and provide the ID threaded through all
steps.

### Steps table

The step record needs to carry:

- `run_id`
- `step_name`
- `step_impl`
- `status`
- `attempt`
- `arguments`
- `output`
- `halt_payload`
- `error`
- timestamps

This is the main durable execution table.

If we later add event history, that can be separate. The core replay logic
should not depend on an event log.

## Threading identity through the run

The runtime needs two stable identities:

### `run_id`

Every durable Reactor execution must have a `run_id`.

That `run_id` is shared by:

- the run record
- every persisted step record
- every resume operation
- every replay lookup

Without a stable `run_id`, replay has no safe persistence boundary.

### `step_name`

For the first version, `step_name` is the obvious step identity because Reactor
already uses it as the dependency handle.

So a downstream dependency lookup can be framed as:

- find step output for `run_id = X`
- where `step_name = :read_weekly_checkin`

That is enough to resolve most replay cases.

If dynamic steps require a stronger identifier later, we can add one. But the
starting point should stay aligned with normal Reactor semantics.

## How replay should work

At runtime, the durable wrapper around a step should follow this sequence:

1. load the persisted step record for `run_id + step_name`
2. if the step already succeeded, return its persisted output immediately
3. if the step previously halted and is waiting for resume, return the halt or
   resume behavior appropriate for that step type
4. otherwise let Reactor resolve the step arguments normally
5. persist the resolved argument payload for the current step
6. execute the underlying Reactor step
7. persist the result

The important point is that Reactor is still doing dependency planning and
argument resolution. Durability just makes that resolution replayable.

## Consequence for upstream dependencies

When a step depends on a prior step result, we should not duplicate the whole
upstream tree into the current record by default.

Instead:

- the current step stores the final arguments it received
- those arguments may include values that came from upstream steps
- the source of those values remains the upstream step records for the same
  `run_id`

This is a cleaner model than trying to store a full recursively-expanded run
snapshot on every step.

## What the library should expose publicly

The public API should stay minimal:

- `use Reactor, extensions: [AshDurableReactor]`
- `durable do ... end`
- `AshDurableReactor.run/4`
- `AshDurableReactor.resume_step/4`
- inspection helpers for runs and steps

Everything else should feel like normal Reactor.

## What this means for the implementation

If we follow this direction, the missing primitives are implementation
primitives, not new user-facing DSL concepts.

We need:

1. a stable `run_id` boundary for every durable run
2. persisted step records keyed by `run_id + step_name`
3. persistence of resolved step arguments
4. persistence of step outputs, halts, and errors
5. replay lookup that can satisfy `result(:upstream_step)` from persisted step outputs
6. resumable step handling built on the same step record model

Those are runtime concerns. The author should not need to learn a second
workflow abstraction.

## Recommended direction

The right path is:

- keep Reactor's DSL intact
- keep Reactor's dependency resolution intact
- treat durability as a wrapper around normal step execution
- persist per-step inputs and outputs under a shared `run_id`
- let downstream steps obtain upstream values from persisted step outputs when replaying

That gives us durability while preserving the exact user experience Reactor
already established.
