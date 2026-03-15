# RecurseRevisionLoop

Demonstrates `recurse` with `AshDurableReactor` — a revision loop that iterates until the draft is approved, then replays from the durable store on a second run with the same `run_id`.

## What it does

1. An inner reactor (`RevisionReactor`) performs a single revision pass: increments revision_number, appends `[revN]` to content, and sets `approved=true` when revision >= 3
2. A parent reactor (`LoopReactor`) uses `recurse` to loop the inner reactor until `draft.approved == true` (max 5 iterations as a safety cap)
3. The demo runs the loop, then runs again with the same `run_id` to show replay (no re-execution of steps)

## How to run

```bash
cd examples/recurse_revision_loop
mix deps.get
mix run -e "RecurseRevisionLoop.Demo.run()"
```
