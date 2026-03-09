defmodule AshPersistence.SqliteRepo do
  use AshSqlite.Repo,
    otp_app: :ash_persistence
end
