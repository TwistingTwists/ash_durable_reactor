# Implementation Overview

This repository now contains a working first pass of a durable Reactor extension, plus example applications that exercise the main persistence and resume flows described in the plan.

## What was built

The core library extends Reactor at the runtime boundary instead of treating durability as a separate persistence helper. Durable execution is centered around:

- a Reactor extension and DSL for durable configuration
- middleware and step wrapping so persistence and replay happen at step boundaries
- persisted run state, step state, undo metadata, and compensation metadata
- halt and resume support through ordinary Reactor step modules that implement `resume/4`

The main validated entrypoint is `AshDurableReactor.run/4`, which prepares a durable reactor, executes it synchronously by default, and replays previously completed steps when the same `run_id` is resumed.

## Persistence model

Two persistence paths exist today.

### Built-in store

The base library includes an ETS-backed store for local development and integration coverage. This keeps the core library runnable without forcing a database dependency.

### Ash-backed store

The more durable direction is modeled through `AshDurableReactor.AshStore`. Instead of this library owning Postgres, SQLite, or ETS adapter logic directly, it reads and writes Ash resources. Backend choice is delegated to Ash data layers:

- `Ash.DataLayer.Ets`
- `AshSqlite.DataLayer`
- `AshPostgres.DataLayer`

That keeps the durability library focused on Reactor semantics while Ash handles storage details, migrations, and adapter differences.

## Examples

Two example applications are included.

### Manual approval example

`examples/manual_approval` shows an end-to-end halt/resume workflow using the durable runtime directly.

### Ash persistence example

`examples/ash_persistence` shows the Ash-resource-backed persistence path. It includes:

- durable run, step, and event resources
- an ETS-backed configuration for zero-setup execution
- a SQLite-backed configuration with generated Ash migrations
- a Postgres-backed configuration showing the same resource model on a different data layer

The key idea is that the resource shape stays consistent while the backend changes underneath via Ash configuration.

## Verification completed

The current implementation was exercised with:

- root library tests
- integration tests for durable replay, undo, and compensation
- the Ash-backed example tests
- SQLite migration generation via `mix ash.codegen`
- SQLite migration execution and demo run inside `examples/ash_persistence`

## Current boundary

This is a durable runtime foundation, not the final shape of the full plan. The repository now proves that Reactor durability can be implemented as an extension with step-level replay and that persistence can be cleanly delegated to Ash resources so the backend is not the library's problem.
