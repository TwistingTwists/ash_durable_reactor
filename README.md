# AshDurableReactor

`AshDurableReactor` adds durable execution semantics to [Reactor](https://hex.pm/packages/reactor).

It currently provides:

- a Reactor extension with a `durable do ... end` config block
- wrapped step execution with persisted run and step state
- an ETS-backed store for local development, tests, and examples
- an Ash-backed store so persistence can be modeled as Ash resources and delegated to Ash data layers
- resumable ordinary Reactor step modules via `resume/4`
- a `AshDurableReactor.run/4` entrypoint that prepares and runs the durable reactor

## Ash-Backed Persistence

If you want persistence to be an Ash concern instead of a library concern, use
the built-in backend shortcuts:

```elixir
durable do
  sqlite repo: MyApp.Repo
end
```

`otp_app` defaults to the top-level namespace from the repo module, so
`MyApp.Repo` infers `:my_app`.

Or:

```elixir
durable do
  postgres repo: MyApp.Repo
end
```

These shortcuts generate the Ash domain/resources internally and route durable
storage through `AshDurableReactor.AshStore`.

## Quick Example

```elixir
defmodule MyApp.ApprovalFlow do
  use Reactor, extensions: [AshDurableReactor]

  durable do
    sqlite repo: MyApp.Repo
    persist_context [:request_id]
  end

  input :amount

  step :build_charge do
    argument :amount, input(:amount)
    run fn %{amount: amount}, _ -> {:ok, %{amount: amount}} end
  end

  step :approval, MyApp.ApprovalStep do
    argument :charge, result(:build_charge)
  end

  step :finalize do
    argument :charge, result(:build_charge)
    argument :approval, result(:approval)
    run fn %{charge: charge, approval: approval}, _ -> {:ok, {charge, approval}} end
  end
end

defmodule MyApp.ApprovalStep do
  use Reactor.Step

  def run(_arguments, _context, _options), do: {:halt, %{awaiting: :approval}}

  def resume(_arguments, _context, _options, persisted_step) do
    {:ok, persisted_step.resume_payload}
  end
end

run_id = "charge-123"

AshDurableReactor.run(MyApp.ApprovalFlow, %{amount: 50}, %{request_id: "req-1"}, run_id: run_id)
# => {:halted, reactor}

AshDurableReactor.resume_step(run_id, :approval, :approved)

AshDurableReactor.run(MyApp.ApprovalFlow, %{amount: 50}, %{request_id: "req-1"}, run_id: run_id)
# => {:ok, {%{amount: 50}, :approved}}
```

## Persistence Contract

The runtime persistence contract is intentionally step-local:

- every durable run has a stable `run_id`
- every step persists its resolved input arguments
- every step persists its own output, halt payload, or error
- downstream replay uses persisted outputs from upstream `run_id + step_name`
- resumable steps stay ordinary Reactor steps and continue through `resume/4`

That means you keep normal Reactor dependency wiring while durability lives at
the step boundary.

## Running The Tests

```bash
mix test
```

## Example App

The canonical runnable example is `examples/ash_persistence`.

Run the SQLite-backed demo with:

```bash
cd examples/ash_persistence
mix ash_sqlite.create
mix ash_sqlite.migrate
mix run -e "AshPersistence.Demo.run_sqlite()"
```

For zero-setup local execution, run the ETS-backed Ash demo with:

```bash
cd examples/ash_persistence
mix run -e "AshPersistence.Demo.run_ets()"
```

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `ash_durable_reactor` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ash_durable_reactor, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/ash_durable_reactor>.
