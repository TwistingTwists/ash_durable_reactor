# ComposeWorkflow

This example demonstrates Reactor composition with `AshDurableReactor`. A parent reactor composes a sub-reactor as a single step, with durable persistence across both.

## What it does

1. **PipelineReactor** (parent) runs three stages: prepare, enrichment (composed), publish
2. **EnrichmentReactor** (sub-reactor) runs enrich + validate steps inside the compose
3. On replay (same `run_id`), wrapped steps are replayed from the store while the compose meta-step re-executes its inner reactor

## Run it

```bash
cd examples/compose_workflow
mix deps.get
mix run -e "ComposeWorkflow.Demo.run()"
```
