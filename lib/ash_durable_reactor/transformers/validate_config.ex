defmodule AshDurableReactor.Transformers.ValidateConfig do
  @moduledoc """
  Spark transformer that validates durable store configuration.

  At compile time it checks that the configured store module looks like a valid
  durable persistence adapter so the extension can fail fast with a DSL error
  instead of producing a broken runtime.
  """

  use Spark.Dsl.Transformer

  alias Spark.Error.DslError

  @impl true
  def transform(dsl_state) do
    store = Spark.Dsl.Transformer.get_option(dsl_state, [:durable], :store) || AshDurableReactor.Store
    module = Spark.Dsl.Transformer.get_persisted(dsl_state, :module)

    if Code.ensure_loaded?(store) and function_exported?(store, :start_run, 1) do
      {:ok, dsl_state}
    else
      {:error,
       DslError.exception(
         module: module,
         path: [:durable, :store],
         message: "Store #{inspect(store)} does not implement AshDurableReactor.StoreBehaviour"
       )}
    end
  end
end
