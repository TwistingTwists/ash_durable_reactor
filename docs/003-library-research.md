# Library Research Notes

This note captures the extension patterns and constraints observed in Reactor itself, `reactor_req`, and `reactor_process`, and how those patterns were applied in this repository.

## Reactor

At a high level, Reactor gives a durable extension three useful hooks:

- DSL translation through Spark extensions, transformers, and verifiers
- runtime interception through middleware
- explicit step semantics for run, retry, compensation, undo, halt, and resume

The important execution constraints for durability are:

- step names are stable identities inside the execution graph
- planning happens against a DAG of dependencies, so replay should preserve step identity and order
- async execution is a real concern because multiple ready steps may run concurrently
- compensation and undo are already first-class Reactor behaviors, so durable replay should persist those outcomes instead of inventing a parallel recovery model

The practical result is that durability belongs at the step boundary: record when a step starts, succeeds, halts, retries, compensates, or undoes; on resume, consult persisted state before re-running the underlying step.

## `reactor_req`

`reactor_req` is intentionally narrow. It extends Reactor by adding a set of DSL entities into the existing `reactor` section with `dsl_patches`, for example `req_get`, `req_post`, and `req_run`.

Key pattern:

- use `Spark.Dsl.Patch.AddEntity` to inject domain-specific steps into the base Reactor DSL without changing Reactor itself

This is a good fit for durable-specific step primitives. That pattern directly informed the resumable wait DSL entity in this repository: durability can add its own step forms while still looking like normal Reactor DSL.

`reactor_req` also includes a small formatter workaround module (`Reactor.Req.Ext`) that mirrors the patched entities in a synthetic extension. That is a reminder that Spark DSL ergonomics matter when an extension relies heavily on patched entities.

## `reactor_process`

`reactor_process` does two things that are directly relevant to durable execution.

First, it adds custom DSL entities with `dsl_patches`, just like `reactor_req`.

Second, it uses a transformer (`Reactor.Process.Dsl.Transformer`) to automatically inject middleware into the reactor definition. That middleware captures process-specific runtime state in `init/1`, and steps rely on that middleware being present.

Key patterns:

- use a transformer to install required middleware automatically
- make runtime invariants explicit instead of assuming callers configured them correctly
- let steps depend on context prepared by middleware

This heavily influenced the durable design here. Durable execution needs runtime state and cross-step context, so middleware should be installed automatically rather than left to user discipline.

`reactor_process` also reinforces that step semantics should stay inside normal Reactor capabilities. Its steps expose undo behavior through standard step callbacks instead of inventing a separate rollback subsystem. That matches the durable design goal of persisting normal Reactor outcomes instead of replacing them.

## How that research changed this library

The design implemented here follows those library patterns closely:

- durability is modeled as a Spark/Reactor extension, not as a wrapper API alone
- durable-specific step syntax is added with DSL patching
- middleware is injected via a transformer rather than requiring manual setup
- replay happens around normal step execution so retry, compensation, and undo remain Reactor-native
- persistence is treated as infrastructure behind the extension, not as the extension itself

The largest architectural change after revisiting the ecosystem was persistence ownership. Instead of baking Postgres or SQLite behavior into the library, the repository now includes `AshDurableReactor.AshStore`, which writes to Ash resources and leaves backend selection to Ash data layers. That aligns the library with Ash's strengths:

- Ash owns data modeling and persistence actions
- Ash codegen owns SQL migration generation where relevant
- the durable extension only needs a resource contract for runs, steps, and optional events

## Takeaway

The durable direction that appears most maintainable is:

1. extend Reactor through normal Spark extension points
2. keep durability logic at the step and middleware layers
3. persist Reactor-native state transitions
4. delegate backend concerns to Ash resources and data layers

That combination keeps the library aligned with the existing Reactor extension ecosystem instead of becoming a separate orchestration system with its own competing abstractions.
