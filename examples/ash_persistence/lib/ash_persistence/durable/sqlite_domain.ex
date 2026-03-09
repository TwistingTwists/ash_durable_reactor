defmodule AshPersistence.Durable.SqliteDomain do
  use Ash.Domain,
    otp_app: :ash_persistence

  resources do
    resource AshPersistence.Durable.Sqlite.Run
    resource AshPersistence.Durable.Sqlite.Step
    resource AshPersistence.Durable.Sqlite.Event
  end
end
