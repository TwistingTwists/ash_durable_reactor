defmodule AshPersistence.PostgresRepo do
  use AshPostgres.Repo,
    otp_app: :ash_persistence,
    warn_on_missing_ash_functions?: false

  def min_pg_version do
    %Version{major: 16, minor: 0, patch: 0}
  end
end
