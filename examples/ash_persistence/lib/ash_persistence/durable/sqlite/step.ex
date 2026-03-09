defmodule AshPersistence.Durable.Sqlite.Step do
  use Ash.Resource,
    domain: AshPersistence.Durable.SqliteDomain,
    data_layer: AshSqlite.DataLayer

  import AshPersistence.Durable.Resource

  sqlite do
    table "durable_steps"
    repo AshPersistence.SqliteRepo
  end

  step_fields()
end
