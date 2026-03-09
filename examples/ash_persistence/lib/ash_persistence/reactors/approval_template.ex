defmodule AshPersistence.Reactors.ApprovalTemplate do
  @moduledoc false

  defmacro __using__(opts) do
    sqlite_opts = Keyword.get(opts, :sqlite)
    postgres_opts = Keyword.get(opts, :postgres)
    store_config = Keyword.get(opts, :store_config, [])

    quote bind_quoted: [
            sqlite_opts: sqlite_opts,
            postgres_opts: postgres_opts,
            store_config: store_config
          ] do
      use Reactor, extensions: [AshDurableReactor]

      durable do
        if sqlite_opts, do: sqlite(sqlite_opts)
        if postgres_opts, do: postgres(postgres_opts)
        if store_config != [] do
          store AshDurableReactor.AshStore
          store_config store_config
        end

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

      step :approval, AshPersistence.Reactors.ApprovalStep do
        argument :order, result(:load_order)
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
