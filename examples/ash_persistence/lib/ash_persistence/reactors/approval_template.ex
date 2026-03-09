defmodule AshPersistence.Reactors.ApprovalTemplate do
  @moduledoc false

  defmacro __using__(opts) do
    store_config = Keyword.fetch!(opts, :store_config)

    quote bind_quoted: [store_config: store_config] do
      use Reactor, extensions: [AshDurableReactor]

      durable do
        store AshDurableReactor.AshStore
        store_config store_config
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

      await_signal :approval do
        signal :manager_approval
      end

      step :capture_payment do
        argument :order, result(:load_order)
        argument :approval, result(:approval)

        run fn %{order: order, approval: approval}, _context ->
          {:ok, %{order: order, approval: approval, status: :captured}}
        end
      end

      return :capture_payment
    end
  end
end
