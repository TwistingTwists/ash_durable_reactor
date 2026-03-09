defmodule AshDurableReactor.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      AshDurableReactor.Store
    ]

    opts = [strategy: :one_for_one, name: AshDurableReactor.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
