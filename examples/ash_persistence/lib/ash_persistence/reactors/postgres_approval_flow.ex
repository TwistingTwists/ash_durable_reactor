defmodule AshPersistence.Reactors.PostgresApprovalFlow do
  use AshPersistence.Reactors.ApprovalTemplate,
    store_config: [
      domain: AshPersistence.Durable.PostgresDomain,
      run_resource: AshPersistence.Durable.Postgres.Run,
      step_resource: AshPersistence.Durable.Postgres.Step,
      event_resource: AshPersistence.Durable.Postgres.Event
    ]
end
