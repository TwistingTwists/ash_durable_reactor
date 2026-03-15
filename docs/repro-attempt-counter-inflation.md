# Repro: `attempt` counter inflated by compose/recurse inner reactors

## Problem

When a composed or recursed inner reactor also declares
`extensions: [AshDurableReactor]`, its middleware calls `Store.start_run/1` on
the **same `run_id`** as the parent. Each call increments `attempt` because the
run already exists.

| Scenario | Expected `attempt` | Actual | Extra |
|----------|-------------------|--------|-------|
| Simple reactor (no compose/recurse) | 1 per run | 1 | 0 |
| Compose with durable inner reactor | 1 per run | 2 | +1 from inner middleware |
| Recurse with durable inner reactor (3 iterations) | 1 per run | 4 | +3 (one per iteration) |

## Root cause

`AshDurableReactor.Middleware.init/1` unconditionally calls `store.start_run/1`.
When Reactor executes a `compose` or `recurse` meta-step, it instantiates the
inner reactor with the parent's context (including `run_id`). If the inner
reactor also has the `AshDurableReactor` extension, its middleware fires `init`
again on the same `run_id`, and `Store.start_run/1` bumps `attempt` on the
existing run record.

Location: `lib/ash_durable_reactor/middleware.ex:19` — `init/1`

## Repro 1: compose (+1 per compose call)

```bash
cd examples/compose_workflow
mix deps.get
mix run -e '
alias AshDurableReactor.Store
Store.reset!()
run_id = "repro-compose"
{:ok, _} = AshDurableReactor.run(
  ComposeWorkflow.PipelineReactor,
  %{raw_data: %{source: "api", payload: "hello"}},
  run_id: run_id
)
run = Store.get_run(run_id)
IO.puts("attempt=#{run.attempt}")
# Expected: 1
# Actual:   2
'
```

## Repro 2: recurse (+1 per iteration)

```bash
cd examples/recurse_revision_loop
mix deps.get
mix run -e '
alias AshDurableReactor.Store
Store.reset!()
run_id = "repro-recurse"
{:ok, _} = AshDurableReactor.run(
  RecurseRevisionLoop.LoopReactor,
  %{draft: %{approved: false, revision_number: 0, content: "draft"}},
  run_id: run_id
)
run = Store.get_run(run_id)
IO.puts("attempt=#{run.attempt}")
# Expected: 1
# Actual:   4 (1 parent + 3 iterations)
'
```

## Repro 3: control — non-durable inner reactor (correct)

```bash
cd examples/compose_workflow
mix deps.get
mix run -e '
defmodule PlainInner do
  use Reactor
  input :data
  step :enrich do
    argument :data, input(:data)
    run fn %{data: d}, _ -> {:ok, Map.put(d, :enriched, true)} end
  end
  return :enrich
end

defmodule DurableOuter do
  use Reactor, extensions: [AshDurableReactor]
  input :raw_data
  step :prepare do
    argument :raw_data, input(:raw_data)
    run fn %{raw_data: d}, _ -> {:ok, d} end
  end
  compose :inner, PlainInner do
    argument :data, result(:prepare)
  end
  return :inner
end

alias AshDurableReactor.Store
Store.reset!()
run_id = "repro-control"
{:ok, _} = AshDurableReactor.run(DurableOuter, %{raw_data: %{x: 1}}, run_id: run_id)
IO.puts("attempt=#{Store.get_run(run_id).attempt}")
# Expected: 1
# Actual:   1 ✓
'
```

## Suggested fix location

`Middleware.init/1` should detect when it is running inside a composed or
recursed sub-reactor and skip the `start_run` call. Possible approaches:

1. Check if `context[:private][:composed_reactors]` already contains a parent
   module that has started this `run_id` — if so, the run is already active.
2. Check if the run already exists and is in `:running` status — if so, skip
   `start_run` entirely (the parent already started it).
3. Have `start_run` not increment `attempt` when the run is already `:running`.
