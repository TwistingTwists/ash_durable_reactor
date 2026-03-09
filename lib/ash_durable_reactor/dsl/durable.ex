defmodule AshDurableReactor.Dsl.Durable do
  @moduledoc false

  def section do
    %Spark.Dsl.Section{
      name: :durable,
      describe: "Configure durable execution for the surrounding reactor.",
      schema: [
        store: [
          type: :module,
          required: false,
          default: AshDurableReactor.Store,
          doc: "Persistence adapter implementing `AshDurableReactor.StoreBehaviour`."
        ],
        store_config: [
          type: :keyword_list,
          required: false,
          default: [],
          doc: "Adapter-specific configuration, for example Ash domain and resource modules."
        ],
        persist_context: [
          type: {:list, :atom},
          required: false,
          default: [],
          doc: "Context keys copied into the run record."
        ],
        default_async?: [
          type: :boolean,
          required: false,
          default: false,
          doc: "Whether wrapped steps should be async by default."
        ],
        max_concurrency: [
          type: :pos_integer,
          required: false,
          default: 1,
          doc: "Suggested maximum concurrency for durable runs."
        ],
        durable_undo?: [
          type: :boolean,
          required: false,
          default: true,
          doc: "Persist undo lifecycle state."
        ],
        durable_compensation?: [
          type: :boolean,
          required: false,
          default: true,
          doc: "Persist compensation lifecycle state."
        ],
        resume_strategy: [
          type: {:in, [:replay]},
          required: false,
          default: :replay,
          doc: "Durable resume strategy."
        ]
      ]
    }
  end
end
