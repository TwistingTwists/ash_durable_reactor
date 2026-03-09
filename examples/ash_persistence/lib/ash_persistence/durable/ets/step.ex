defmodule AshPersistence.Durable.Ets.Step do
  use Ash.Resource,
    domain: AshPersistence.Durable.EtsDomain,
    data_layer: Ash.DataLayer.Ets

  import AshPersistence.Durable.Resource

  ets do
    table :durable_steps_ets
    private? false
  end

  step_fields()
end
