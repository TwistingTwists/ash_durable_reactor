defmodule AshPersistence.Reactors.EtsApprovalFlow do
  use AshPersistence.Reactors.ApprovalTemplate,
    store_config: [
      domain: AshPersistence.Durable.EtsDomain,
      run_resource: AshPersistence.Durable.Ets.Run,
      step_resource: AshPersistence.Durable.Ets.Step,
      event_resource: AshPersistence.Durable.Ets.Event
    ]
end
