# ManualApproval

This example shows a full halt/resume flow using `AshDurableReactor`.

Run it with:

```bash
cd examples/manual_approval
mix deps.get
mix run -e "ManualApproval.Demo.run()"
```

The script will:

1. start a durable run
2. halt waiting for a manager approval signal
3. record the signal
4. resume the same run with the same `run_id`
5. print the persisted run and step records

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `manual_approval` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:manual_approval, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/manual_approval>.
