# Accountability Agent API Sketch

This is an example-first proposal for how writing a durable agent should feel.
It is intentionally not constrained by the current implementation. The goal is
to settle the public API before we add the missing primitives.

## What feels wrong in the current example

The current `examples/accountability_workflow` reactor proves the runtime
mechanics, but it is still too low-level for agent authoring:

- every step has to manually wire `argument :x, input(:...)` and `argument :y, result(:...)`
- durable state lives implicitly in Reactor dependencies instead of in a clear agent state model
- side effects like sending a message are not first-class
- waiting for a reply is modeled as a bare `await_resume` instead of as a normal agent action
- authors have to think about replay mechanics while writing business logic

For an agent DSL, the author should mostly answer:

1. what state do I need to read?
2. what new state does this step produce?
3. is this step pure, effectful, or waiting on the outside world?

## Proposed authoring experience

```elixir
defmodule AccountabilityWorkflow.Agent do
  use AshDurableReactor.Agent

  durable do
    sqlite repo: MyApp.Repo
  end

  input :config
  input :phase

  step :resolve_context do
    reads [:config]
    run AccountabilityWorkflow.Steps.ResolveContext
    writes [:project, :trigger_type, :week, :today, :paths]
  end

  step :load_weekly_checkin do
    reads [:project, :week, :paths]
    run AccountabilityWorkflow.Steps.LoadWeeklyCheckin
    writes :week_data
  end

  step :check_today do
    reads [:today, :week_data]
    run AccountabilityWorkflow.Steps.CheckToday
    writes :today_status
  end

  step :build_message do
    reads [:phase, :trigger_type, :today_status, :week_data, :paths]
    run AccountabilityWorkflow.Steps.BuildMessage
    writes :outbound_message
  end

  step :send_message do
    reads [:outbound_message]
    effect AccountabilityWorkflow.Steps.SendMessage
    writes :delivery
  end

  await :checkin_reply do
    reads [:delivery, :outbound_message]
    resume_with :message_reply
    writes :reply
    timeout {:days, 1}
  end

  step :record_checkin do
    reads [
      :config,
      :phase,
      :today,
      :week_data,
      :today_status,
      :outbound_message,
      :delivery,
      :reply
    ]

    effect AccountabilityWorkflow.Steps.RecordCheckin
    writes :checkin_record
  end

  return :checkin_record
end
```

## Why this is simpler

The author does not manually connect `input/1`, `result/1`, and `argument/2` for
every edge in the graph. They declare state dependencies with `reads` and
outputs with `writes`.

That gives us one durable state namespace for the whole run:

- initial inputs are state slots
- each step writes one or more new state slots
- later steps read those slots by name
- the runtime persists the resolved `reads` payload for each step as its durable boundary

For agent workflows, that is much easier to read than explicit Reactor argument
wiring on every step.

## Semantics of the proposed primitives

### `reads`

`reads [:config, :week_data, :reply]` means:

- resolve these values from run inputs or prior `writes`
- pass the resolved map to the step implementation
- persist that resolved payload as the step's execution input

This becomes the default durable checkpoint boundary.

### `writes`

`writes :week_data` or `writes [:project, :week, :today]` means:

- take the step result
- project it into named durable state slots
- make those slots available to later steps

If a step writes multiple keys, the implementation returns a map. If it writes
one key, the implementation may return a single value or a one-key map.

### `run`

`run` is for replayable, deterministic work:

- reading files
- computing prompt context
- transforming state
- parsing model outputs

If the step has already succeeded for the same run, the runtime replays the
persisted output instead of re-running it.

### `effect`

`effect` is for side effects that should happen once:

- sending a message
- calling an external API that creates or mutates state
- writing a durable record

The runtime still persists the resolved inputs and outputs, but the semantic
intent is different: on replay, we do not want to re-emit the side effect if the
step already succeeded.

### `await`

`await` is the first-class pause point for an external event:

- it declares what run state is visible while waiting
- it declares the resume contract (`resume_with :message_reply`)
- it stores the resumed payload into a state slot with `writes`

This should be the agent-facing primitive instead of exposing `await_resume`
directly.

## What this likely compiles to

This proposal does not require abandoning Reactor. It can compile down to the
current durable Reactor model:

- `reads` compiles to normal Reactor arguments
- `writes` compiles to durable state projection plus a normal step result
- `run` maps to a replayable durable step
- `effect` maps to a "run once, replay output later" durable step mode
- `await` maps to a resumable step plus a persisted resume payload contract

So the agent API can be a thinner layer over the existing execution engine
rather than a second runtime.

## New library primitives implied by this example

To support the example cleanly, the library needs a few first-class concepts
that do not exist yet or are only implicit today.

### 1. Durable state slots

We need a run-level state namespace where:

- inputs are addressable by name
- steps can write named values
- later steps can read those values without explicit `result(:step)` wiring

### 2. Read/write projection

The runtime needs to understand:

- how `reads` resolve into a step payload
- how `writes` project a result back into durable state

That projection logic is part of the public programming model, not just a store
detail.

### 3. Step intent

The runtime needs a first-class distinction between:

- replayable computation
- effect-once steps
- wait-for-resume steps

Today that intent is mostly encoded indirectly.

### 4. Resume contracts

`await` should let us declare:

- the event name or resume channel
- optional timeout behavior
- where the resumed payload lands in durable state

That is more expressive than a generic "resume this step with any value".

### 5. Step payload persistence by default

For agent use cases, we should persist the fully resolved `reads` payload for
each step automatically. That is more useful than relying mainly on
`persist_context`.

### 6. Event history

Once steps have explicit intents, the event log becomes much clearer:

- `step_started`
- `step_succeeded`
- `effect_emitted`
- `await_started`
- `await_resumed`
- `step_failed`

That history will matter for debugging real agents.

## What we should avoid in the public API

This example deliberately avoids a few things that make the current shape feel
too low-level for agent authors:

- repeating `argument :x, result(:step)` everywhere
- exposing `await_resume` as the main authoring primitive
- making `persist_context` the main way data survives a pause
- forcing authors to model every durable value as raw Reactor plumbing

## Open questions for discussion

These are the main design choices still worth debating before we touch the
runtime:

1. Should the top-level API be `use AshDurableReactor.Agent` or still `use Reactor, extensions: [AshDurableReactor]` with extra DSL entities?
2. Should `writes` support nested paths like `[:message, :delivery]`, or should state stay flat at first?
3. Should `effect` be its own keyword, or should this remain a `step` with `mode :effect_once`?
4. Should `await` support typed resume payload validation from day one?
5. Should `reads` be able to rename keys, or should the first version keep names identical between state and step arguments?

The main point of this sketch is that the durable agent API should be centered
on state transitions and pause points, not on hand-written dependency plumbing.
