defmodule AshPersistence.Reactors.PostgresApprovalFlow do
  use AshPersistence.Reactors.ApprovalTemplate,
    postgres: [repo: AshPersistence.PostgresRepo, otp_app: :ash_persistence]
end
