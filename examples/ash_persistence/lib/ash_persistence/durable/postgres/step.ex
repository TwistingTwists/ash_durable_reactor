defmodule AshPersistence.Durable.Postgres.Step do
  use Ash.Resource,
    domain: AshPersistence.Durable.PostgresDomain,
    data_layer: AshPostgres.DataLayer

  import AshPersistence.Durable.Resource

  postgres do
    table "durable_steps"
    repo AshPersistence.PostgresRepo
  end

  step_fields()
end
