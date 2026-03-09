# AccountabilityWorkflow

This example shows the Reactor-native accountability agent shape with
`AshDurableReactor`.

It demonstrates:

- plain Reactor `input`, `step`, `argument`, and `result`
- default replayable durability on ordinary steps
- one resumable ordinary step implemented via `resume/4`
- step replay after resume using the same `run_id`
- a Telegram delivery stub that just prints to stdout

The important design point is that this does **not** introduce a second agent
DSL. The workflow stays ordinary Reactor code, and `AshDurableReactor` adds a
durable wrapper around each step.

That means:

- normal Reactor dependency wiring (`result(:previous_step)`, `input(:config)`)
- step outputs are persisted per `run_id + step_name`
- downstream steps replay those persisted outputs instead of re-running upstream work

The canonical example module is
`AccountabilityWorkflow.ReactorNative`.

## Run It

```bash
cd examples/accountability_workflow
mix deps.get
mix run -e "AccountabilityWorkflow.Demo.run()"
```
