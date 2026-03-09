import Config

config :ash_persistence,
  ash_domains: [AshPersistence.Durable.SqliteDomain],
  ecto_repos: [AshPersistence.SqliteRepo]

config :ash_persistence, AshPersistence.SqliteRepo,
  database: Path.expand("../priv/sqlite/durable.sqlite", __DIR__),
  pool_size: 5,
  stacktrace: true,
  show_sensitive_data_on_connection_error: true

config :ash_persistence, AshPersistence.PostgresRepo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "ash_persistence_dev",
  pool_size: 5,
  stacktrace: true,
  show_sensitive_data_on_connection_error: true

config :ash_durable_reactor, :ash_store,
  domain: AshPersistence.Durable.SqliteDomain,
  run_resource: AshPersistence.Durable.Sqlite.Run,
  step_resource: AshPersistence.Durable.Sqlite.Step,
  event_resource: AshPersistence.Durable.Sqlite.Event
