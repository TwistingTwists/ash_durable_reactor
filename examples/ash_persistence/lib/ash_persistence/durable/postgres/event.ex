defmodule AshPersistence.Durable.Postgres.Event do
  use Ash.Resource,
    domain: AshPersistence.Durable.PostgresDomain,
    data_layer: AshPostgres.DataLayer

  import AshPersistence.Durable.Resource

  postgres do
    table "durable_events"
    repo AshPersistence.PostgresRepo
  end

  event_fields()
end
