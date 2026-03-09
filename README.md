# AshDurableReactor

`AshDurableReactor` adds durable execution semantics to [Reactor](https://hex.pm/packages/reactor).

It currently provides:

- a Reactor extension with a `durable do ... end` config block
- wrapped step execution with persisted run and step state
- an ETS-backed store for local development, tests, and examples
- an `await_signal` step for manual approval and other interruptible workflows
- a `AshDurableReactor.run/4` entrypoint that prepares and runs the durable reactor

## Quick Example

```elixir
defmodule MyApp.ApprovalFlow do
  use Reactor, extensions: [AshDurableReactor]

  durable do
    persist_context [:request_id]
  end

  input :amount

  step :build_charge do
    argument :amount, input(:amount)
    run fn %{amount: amount}, _ -> {:ok, %{amount: amount}} end
  end

  await_signal :approval do
    signal :manager_approval
  end

  step :finalize do
    argument :charge, result(:build_charge)
    argument :approval, result(:approval)
    run fn %{charge: charge, approval: approval}, _ -> {:ok, {charge, approval}} end
  end
end

run_id = "charge-123"

AshDurableReactor.run(MyApp.ApprovalFlow, %{amount: 50}, %{request_id: "req-1"}, run_id: run_id)
# => {:halted, reactor}

AshDurableReactor.signal(run_id, :manager_approval, :approved)

AshDurableReactor.run(MyApp.ApprovalFlow, %{amount: 50}, %{request_id: "req-1"}, run_id: run_id)
# => {:ok, {%{amount: 50}, :approved}}
```

## Running The Tests

```bash
mix test
```

## Example App

There is a runnable end-to-end example in `examples/manual_approval`.

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
