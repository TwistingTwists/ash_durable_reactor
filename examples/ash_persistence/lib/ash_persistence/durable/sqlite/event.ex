defmodule AshPersistence.Durable.Sqlite.Event do
  use Ash.Resource,
    domain: AshPersistence.Durable.SqliteDomain,
    data_layer: AshSqlite.DataLayer

  import AshPersistence.Durable.Resource

  sqlite do
    table "durable_events"
    repo AshPersistence.SqliteRepo
  end

  event_fields()
end
