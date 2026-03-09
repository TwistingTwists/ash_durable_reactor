defmodule AshDurableReactor.TestCounter do
  @moduledoc false

  use Agent

  def start_link(_opts) do
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end

  def reset! do
    Agent.update(__MODULE__, fn _ -> %{} end)
  end

  def bump(key) do
    Agent.get_and_update(__MODULE__, fn state ->
      next = Map.update(state, key, 1, &(&1 + 1))
      {Map.fetch!(next, key), next}
    end)
  end

  def get(key) do
    Agent.get(__MODULE__, &Map.get(&1, key, 0))
  end
end
