defmodule AshPersistence.Demo do
  @moduledoc false

  alias AshPersistence.Reactors.{EtsApprovalFlow, SqliteApprovalFlow}

  def run_ets do
    configure_store(
      domain: AshPersistence.Durable.EtsDomain,
      run_resource: AshPersistence.Durable.Ets.Run,
      step_resource: AshPersistence.Durable.Ets.Step,
      event_resource: AshPersistence.Durable.Ets.Event
    )

    stop_ets_tables()
    run_demo(EtsApprovalFlow, "ets-demo")
  end

  def run_sqlite do
    configure_store(
      domain: AshPersistence.Durable.SqliteDomain,
      run_resource: AshPersistence.Durable.Sqlite.Run,
      step_resource: AshPersistence.Durable.Sqlite.Step,
      event_resource: AshPersistence.Durable.Sqlite.Event
    )

    run_demo(SqliteApprovalFlow, "sqlite-demo")
  end

  defp run_demo(reactor, run_id) do
    first =
      AshDurableReactor.run(
        reactor,
        %{order_id: "order-1001", amount: 1250},
        %{request_id: "req-1"},
        run_id: run_id
      )

    IO.inspect(first, label: "first run")
    IO.inspect(AshDurableReactor.get_run(run_id, AshDurableReactor.AshStore), label: "persisted run")
    IO.inspect(AshDurableReactor.list_steps(run_id, AshDurableReactor.AshStore), label: "persisted steps")

    :ok = AshDurableReactor.signal(run_id, :manager_approval, %{approved_by: "manager-7"}, AshDurableReactor.AshStore)

    second =
      AshDurableReactor.run(
        reactor,
        %{order_id: "order-1001", amount: 1250},
        %{request_id: "req-1"},
        run_id: run_id
      )

    IO.inspect(second, label: "second run")
    IO.inspect(AshDurableReactor.get_run(run_id, AshDurableReactor.AshStore), label: "persisted run after resume")
    IO.inspect(AshDurableReactor.list_steps(run_id, AshDurableReactor.AshStore), label: "persisted steps after resume")
  end

  defp configure_store(config) do
    Application.put_env(:ash_durable_reactor, :ash_store, config)
  end

  defp stop_ets_tables do
    for resource <- [
          AshPersistence.Durable.Ets.Run,
          AshPersistence.Durable.Ets.Step,
          AshPersistence.Durable.Ets.Event
        ] do
      Ash.DataLayer.Ets.stop(resource)
    end
  end
end
