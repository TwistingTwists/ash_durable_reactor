# Changelog

## 0.2.0

### Fixed

- Compose and recurse sub-reactors no longer inflate the run `attempt` counter.
  Inner reactors sharing the parent `run_id` are now detected as sub-reactors;
  their middleware skips all run-level callbacks (start, complete, halt, error).
- `ash_persistence` SQLite example works out of the box — database creation and
  migrations run automatically on first use.

### Added

- `started_at` and `completed_at` timestamps on step records, `completed_at` on
  run records. Both the library backend resources and the example Ash resources
  now persist these fields, matching the ETS store behaviour.
- Five runnable examples: `accountability_workflow`, `ash_persistence`,
  `compose_workflow`, `manual_approval`, `recurse_revision_loop`.

## 0.1.0

Initial release.

- Reactor extension with `durable do ... end` config block
- Wrapped step execution with persisted run and step state
- ETS-backed store for local development and tests
- Ash-backed store with SQLite and Postgres backend shortcuts
- Resumable step modules via `resume/4`
- `AshDurableReactor.run/4` entrypoint
