defmodule AshPersistence.Durable.Ets.Run do
  use Ash.Resource,
    domain: AshPersistence.Durable.EtsDomain,
    data_layer: Ash.DataLayer.Ets

  import AshPersistence.Durable.Resource

  ets do
    table :durable_runs_ets
    private? false
  end

  run_fields()
end
