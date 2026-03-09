defmodule ManualApproval.Demo do
  @moduledoc false

  alias AshDurableReactor.Store
  alias ManualApproval.OrderApprovalReactor

  def run do
    run_id = "manual-approval-demo"
    Store.reset!()

    IO.puts("Starting durable run #{run_id}")

    first_result =
      AshDurableReactor.run(
        OrderApprovalReactor,
        %{order_id: "order-1001", amount: 1250},
        %{request_id: "req-demo-1"},
        run_id: run_id
      )

    IO.inspect(first_result, label: "first run")
    IO.inspect(AshDurableReactor.get_run(run_id), label: "persisted run after halt")
    IO.inspect(AshDurableReactor.list_steps(run_id), label: "persisted steps after halt")

    :ok = AshDurableReactor.resume_step(run_id, :manager_approval, %{approved_by: "manager-7"})

    second_result =
      AshDurableReactor.run(
        OrderApprovalReactor,
        %{order_id: "order-1001", amount: 1250},
        %{request_id: "req-demo-1"},
        run_id: run_id
      )

    IO.inspect(second_result, label: "second run")
    IO.inspect(AshDurableReactor.get_run(run_id), label: "persisted run after resume")
    IO.inspect(AshDurableReactor.list_steps(run_id), label: "persisted steps after resume")
  end
end
