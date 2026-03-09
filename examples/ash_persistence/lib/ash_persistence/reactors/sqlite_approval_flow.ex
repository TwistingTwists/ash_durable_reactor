defmodule AshPersistence.Reactors.SqliteApprovalFlow do
  use AshPersistence.Reactors.ApprovalTemplate,
    store_config: [
      domain: AshPersistence.Durable.SqliteDomain,
      run_resource: AshPersistence.Durable.Sqlite.Run,
      step_resource: AshPersistence.Durable.Sqlite.Step,
      event_resource: AshPersistence.Durable.Sqlite.Event
    ]
end
