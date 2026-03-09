defmodule AshPersistence.Durable.EtsDomain do
  use Ash.Domain,
    otp_app: :ash_persistence,
    validate_config_inclusion?: false

  resources do
    resource AshPersistence.Durable.Ets.Run
    resource AshPersistence.Durable.Ets.Step
    resource AshPersistence.Durable.Ets.Event
  end
end
