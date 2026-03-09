defmodule AshDurableReactor.Steps.AwaitSignal do
  @moduledoc """
  Wait for an externally recorded signal before continuing.
  """

  use Reactor.Step

  @impl true
  def run(_arguments, context, options) do
    signal_name = Keyword.fetch!(options, :signal)
    store = context[AshDurableReactor].config.store

    case store.get_signal(context.run_id, signal_name) do
      {:ok, value} -> {:ok, value}
      :error -> {:halt, %{awaiting: signal_name}}
    end
  end

  @impl true
  def async?(_), do: false
end
