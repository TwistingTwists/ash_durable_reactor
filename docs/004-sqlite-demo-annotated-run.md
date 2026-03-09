# SQLite Demo Annotated Run

This note captures a real run of:

```bash
cd examples/ash_persistence && mix ash_sqlite.create && mix ash_sqlite.migrate && mix run -e "AshPersistence.Demo.run_sqlite()"
```

The output below is annotated with `{agent_annotation}` to explain what happened at each stage.

## Setup

```text
10:40:08.568 [debug] QUERY OK source="durable_runs" ... ["sqlite-demo-1"]
10:40:08.625 [debug] QUERY OK source="durable_runs" ... ["sqlite-demo-1", 1]
10:40:08.649 [debug] QUERY OK source="durable_runs"
INSERT INTO "durable_runs" ... "sqlite-demo-1" ...
```

{agent_annotation}: The demo now uses a fresh `run_id` each time. There was no existing run row for `sqlite-demo-1`, so the durable runtime created a new run record instead of resuming old state.

## First Run: Execute Until Halt

```text
10:40:08.668 [debug] ... "run_start" ... "load_order"
10:40:08.678 [debug] INSERT INTO "durable_steps" ... "load_order" ...
10:40:08.705 [debug] UPDATE "durable_steps" ... "load_order" ... "succeeded"

10:40:08.709 [debug] ... "run_start" ... "approval"
10:40:08.712 [debug] INSERT INTO "durable_steps" ... "approval" ... "resumable"
10:40:08.713 [debug] UPDATE "durable_steps" ... "approval" ... "halted"
10:40:08.714 [debug] ... "run_halt" ... "approval"
10:40:08.719 [debug] UPDATE "durable_runs" ... "halted"
```

{agent_annotation}: `load_order` is a normal replayable step, so it executes and is persisted as `:succeeded`.

{agent_annotation}: `approval` is the resumable wait step. Its first execution does not complete; it persists a halted step row with `halt_payload: %{awaiting: :approval}` and the run is marked `:halted`.

```text
first run: {:halted, %Reactor{...}}
```

{agent_annotation}: This is the expected first-phase outcome. The reactor stopped at the resumable step and returned a halted reactor state.

## Persisted State After Halt

```text
persisted run: %{
  status: :halted,
  run_id: "sqlite-demo-1",
  halt_reason: %{"payload" => %{"awaiting" => "approval"}, "step" => "approval"},
  ...
}
```

{agent_annotation}: The run row shows that execution paused at the `approval` step.

```text
persisted steps: [
  %{
    step_name: :approval,
    status: :halted,
    mode: :resumable,
    resume_payload: nil,
    halt_payload: %{"awaiting" => "approval"},
    ...
  },
  %{
    step_name: :load_order,
    status: :succeeded,
    mode: :replayable,
    ...
  }
]
```

{agent_annotation}: The durable store contains:

- one completed replayable checkpoint for `load_order`
- one halted resumable checkpoint for `approval`

That is the exact boundary the second run resumes from.

## Resume Request

```text
10:40:08.728 [debug] SELECT ... FROM "durable_steps" ... ["sqlite-demo-1", "approval"]
10:40:08.729 [debug] UPDATE "durable_steps" ...
  SET "resume_payload" = %{approved_by: "manager-7"},
      "resumed_at" = ...
```

{agent_annotation}: `AshDurableReactor.resume_step/4` writes the resume payload onto the halted step row itself. There is no separate signal row or signal store anymore.

## Second Run: Replay + Resume

```text
10:40:08.731 [debug] UPDATE "durable_runs" ... "running"

10:40:08.732 [debug] ... "run_start" ... "load_order"
10:40:08.733 [debug] ... "run_complete" ... "load_order"
```

{agent_annotation}: The second run starts from the top of the graph, but `load_order` is replayable and already succeeded, so the durable runtime can satisfy that step from persisted state while still recording lifecycle events.

```text
10:40:08.734 [debug] ... "run_start" ... "approval"
10:40:08.736 [debug] UPDATE "durable_steps" ... "approval" ... "running"
10:40:08.737 [debug] UPDATE "durable_steps" ... "approval" ... "succeeded"
10:40:08.738 [debug] ... "run_complete" ... "approval"
```

{agent_annotation}: Because the halted `approval` step now has a `resume_payload`, the resumable step completes successfully on replay and returns the stored resume data as its output.

```text
10:40:08.738 [debug] ... "run_start" ... "capture_payment"
10:40:08.740 [debug] INSERT INTO "durable_steps" ... "capture_payment" ...
10:40:08.741 [debug] UPDATE "durable_steps" ... "capture_payment" ... "succeeded"
10:40:08.743 [debug] UPDATE "durable_runs" ... "succeeded"
```

{agent_annotation}: With both upstream values now available:

- `load_order` output
- resumed `approval` output

the downstream `capture_payment` step runs and the whole durable run completes successfully.

```text
second run: {:ok,
 %{
   status: :captured,
   approval: %{"approved_by" => "manager-7"},
   order: %{"amount" => 1250, "currency" => "USD", "id" => "order-1001"}
 }}
```

{agent_annotation}: This is the expected second-phase outcome: the resumed workflow finishes and returns the final business result.

## Persisted State After Resume

```text
persisted run after resume: %{
  status: :succeeded,
  run_id: "sqlite-demo-1",
  result: %{
    "approval" => %{"approved_by" => "manager-7"},
    "order" => %{"amount" => 1250, "currency" => "USD", "id" => "order-1001"},
    "status" => "captured"
  },
  ...
}
```

{agent_annotation}: The run row is now terminal and stores the final output.

```text
persisted steps after resume: [
  %{step_name: :approval, status: :succeeded, mode: :resumable, attempt: 2, ...},
  %{step_name: :capture_payment, status: :succeeded, mode: :replayable, ...},
  %{step_name: :load_order, status: :succeeded, mode: :replayable, ...}
]
```

{agent_annotation}: Final checkpoint state:

- `approval` moved from `:halted` to `:succeeded`
- `capture_payment` was created and completed
- `load_order` remains a replayable success checkpoint

## Takeaway

The example now consistently demonstrates the intended two-phase durable flow:

1. first run halts at a resumable step
2. external code writes `resume_payload` onto that halted step
3. second run replays the graph and unblocks the resumable step
4. downstream work completes and the run is marked `:succeeded`
