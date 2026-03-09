defmodule AshDurableReactor.Dsl.Durable do
  @moduledoc """
  Defines the `durable do ... end` extension section.

  This section configures run-level durability concerns such as which store to
  use and which resume strategy the runtime should apply.
  """

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
        sqlite: [
          type:
            {:keyword_list,
             [repo: [type: :module, required: true], otp_app: [type: :atom, required: false]]},
          required: false,
          doc: "Opt into the built-in AshSqlite durable store wiring."
        ],
        postgres: [
          type:
            {:keyword_list,
             [repo: [type: :module, required: true], otp_app: [type: :atom, required: false]]},
          required: false,
          doc: "Opt into the built-in AshPostgres durable store wiring."
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
