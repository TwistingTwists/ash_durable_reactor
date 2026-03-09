defmodule AshPersistence.Durable.Postgres.Run do
  use Ash.Resource,
    domain: AshPersistence.Durable.PostgresDomain,
    data_layer: AshPostgres.DataLayer

  import AshPersistence.Durable.Resource

  postgres do
    table "durable_runs"
    repo AshPersistence.PostgresRepo
  end

  run_fields()
end
