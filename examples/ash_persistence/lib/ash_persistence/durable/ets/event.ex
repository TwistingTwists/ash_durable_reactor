defmodule AshPersistence.Durable.Ets.Event do
  use Ash.Resource,
    domain: AshPersistence.Durable.EtsDomain,
    data_layer: Ash.DataLayer.Ets

  import AshPersistence.Durable.Resource

  ets do
    table :durable_events_ets
    private? false
  end

  event_fields()
end
