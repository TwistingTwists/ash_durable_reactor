defmodule AshPersistence.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      AshPersistence.SqliteRepo
    ]

    opts = [strategy: :one_for_one, name: AshPersistence.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
