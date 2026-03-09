defmodule AshPersistence.Reactors.SqliteApprovalFlow do
  use AshPersistence.Reactors.ApprovalTemplate,
    sqlite: [repo: AshPersistence.SqliteRepo, otp_app: :ash_persistence]
end
