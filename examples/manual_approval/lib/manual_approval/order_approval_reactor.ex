defmodule ManualApproval.OrderApprovalReactor do
  use Reactor, extensions: [AshDurableReactor]

  input :order_id
  input :amount

  step :load_order do
    argument :order_id, input(:order_id)
    argument :amount, input(:amount)

    run fn %{order_id: order_id, amount: amount}, _context ->
      {:ok, %{id: order_id, amount: amount, currency: "USD"}}
    end
  end

  step :manager_approval, __MODULE__.ManagerApproval do
    argument :order, result(:load_order)
  end

  step :capture_payment do
    argument :order, result(:load_order)
    argument :approval, result(:manager_approval)

    run fn %{order: order, approval: approval}, _context ->
      {:ok, %{order: order, approval: approval, status: :captured}}
    end
  end

  return :capture_payment

  defmodule ManagerApproval do
    use Reactor.Step

    @impl true
    def run(%{order: order}, _context, _options) do
      {:halt, %{awaiting: :manager_approval, order_id: order.id}}
    end

    def resume(_arguments, _context, _options, persisted_step) do
      {:ok, persisted_step.resume_payload}
    end
  end
end
