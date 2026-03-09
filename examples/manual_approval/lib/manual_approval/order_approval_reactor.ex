defmodule ManualApproval.OrderApprovalReactor do
  use Reactor, extensions: [AshDurableReactor]

  durable do
    persist_context [:request_id]
  end

  input :order_id
  input :amount

  step :load_order do
    argument :order_id, input(:order_id)
    argument :amount, input(:amount)

    run fn %{order_id: order_id, amount: amount}, _context ->
      {:ok, %{id: order_id, amount: amount, currency: "USD"}}
    end
  end

  await_resume :manager_approval

  step :capture_payment do
    argument :order, result(:load_order)
    argument :approval, result(:manager_approval)

    run fn %{order: order, approval: approval}, _context ->
      {:ok, %{order: order, approval: approval, status: :captured}}
    end
  end

  return :capture_payment
end
