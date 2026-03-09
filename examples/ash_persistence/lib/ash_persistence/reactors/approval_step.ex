defmodule AshPersistence.Reactors.ApprovalStep do
  use Reactor.Step

  @impl true
  def run(%{order: order}, _context, _options) do
    {:halt, %{awaiting: :approval, order_id: order.id}}
  end

  def resume(_arguments, _context, _options, persisted_step) do
    {:ok, persisted_step.resume_payload}
  end
end
