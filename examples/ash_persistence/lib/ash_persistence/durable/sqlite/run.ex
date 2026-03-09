defmodule AshPersistence.Durable.Sqlite.Run do
  use Ash.Resource,
    domain: AshPersistence.Durable.SqliteDomain,
    data_layer: AshSqlite.DataLayer

  import AshPersistence.Durable.Resource

  sqlite do
    table "durable_runs"
    repo AshPersistence.SqliteRepo
  end

  run_fields()
end
