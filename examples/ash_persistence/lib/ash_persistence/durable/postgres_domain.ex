defmodule AshPersistence.Durable.PostgresDomain do
  use Ash.Domain,
    otp_app: :ash_persistence,
    validate_config_inclusion?: false

  resources do
    resource AshPersistence.Durable.Postgres.Run
    resource AshPersistence.Durable.Postgres.Step
    resource AshPersistence.Durable.Postgres.Event
  end
end
