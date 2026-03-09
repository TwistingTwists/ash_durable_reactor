defmodule AshPersistence.AshStoreEtsTest do
  use ExUnit.Case, async: false

  alias AshPersistence.Reactors.EtsApprovalFlow

  setup do
    Application.put_env(:ash_durable_reactor, :ash_store,
      domain: AshPersistence.Durable.EtsDomain,
      run_resource: AshPersistence.Durable.Ets.Run,
      step_resource: AshPersistence.Durable.Ets.Step,
      event_resource: AshPersistence.Durable.Ets.Event
    )

    for resource <- [
          AshPersistence.Durable.Ets.Run,
          AshPersistence.Durable.Ets.Step,
          AshPersistence.Durable.Ets.Event
        ] do
      Ash.DataLayer.Ets.stop(resource)
    end

    :ok
  end

  test "persists a halted run through Ash resources and resumes it" do
    run_id = "ets-approval-1"

    assert {:halted, _reactor} =
             AshDurableReactor.run(
               EtsApprovalFlow,
               %{order_id: "order-1", amount: 99},
               %{request_id: "req-ets"},
               run_id: run_id
             )

    assert %{status: :halted} = AshDurableReactor.get_run(run_id, AshDurableReactor.AshStore)
    assert %{status: :succeeded} = AshDurableReactor.get_step(run_id, :load_order, AshDurableReactor.AshStore)

    assert :ok =
             AshDurableReactor.resume_step(
               run_id,
               :approval,
               %{approved_by: "manager"},
               AshDurableReactor.AshStore
             )

    assert {:ok, %{status: :captured}} =
             AshDurableReactor.run(
               EtsApprovalFlow,
               %{order_id: "order-1", amount: 99},
               %{request_id: "req-ets"},
               run_id: run_id
             )
  end
end
