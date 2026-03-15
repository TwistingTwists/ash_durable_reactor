# AshPersistence

This example shows how to persist durable Reactor runs through Ash resources so
the backend becomes an Ash data-layer choice instead of a library concern.

Included backends:

- SQLite via `AshSqlite.DataLayer`
- ETS via `Ash.DataLayer.Ets`
- Postgres via `AshPostgres.DataLayer`

## Run The Demos

Both demos work out of the box after fetching dependencies:

```bash
mix deps.get
```

ETS (in-memory, no database needed):

```bash
mix run -e "AshPersistence.Demo.run_ets()"
```

SQLite (auto-creates the database and runs migrations on first use):

```bash
mix run -e "AshPersistence.Demo.run_sqlite()"
```

## Regenerating Migrations

The checked-in migrations live in `priv/sqlite_repo/migrations/` and are
generated from the SQLite resources. To regenerate after schema changes:

```bash
mix ash.codegen durable_sqlite_backend
```

## Switching To Postgres

The Postgres resources already exist under `lib/ash_persistence/durable/postgres/`.
To make them the active persistence backend:

1. Change `config :ash_persistence, ash_domains: [...]` to `AshPersistence.Durable.PostgresDomain`.
2. Change `config :ash_durable_reactor, :ash_store` to the Postgres resource modules.
3. Start `AshPersistence.PostgresRepo` in the application supervision tree.
4. Run `mix ash.codegen durable_postgres_backend`.
5. Run `mix ash_postgres.create && mix ash_postgres.migrate`.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `ash_persistence` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ash_persistence, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/ash_persistence>.
