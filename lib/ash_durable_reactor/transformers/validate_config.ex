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
    module = Spark.Dsl.Transformer.get_persisted(dsl_state, :module)

    store =
      case AshDurableReactor.Backend.resolve_from_dsl_state(dsl_state) do
        {:ok, %{store: store}} ->
          store

        {:error, :multiple_backends} ->
          return_backend_error(
            module,
            "Choose only one durable backend. `sqlite` and `postgres` cannot both be configured."
          )

        {:error, :mixed_backend_and_manual_store} ->
          return_backend_error(
            module,
            "Backend shortcuts cannot be combined with manual `store` or `store_config` options."
          )
      end

    case Code.ensure_compiled(store) do
      {:module, _} ->
        if function_exported?(store, :start_run, 1) do
          {:ok, dsl_state}
        else
          {:error,
           DslError.exception(
             module: module,
             path: [:durable, :store],
             message:
               "Store #{inspect(store)} does not implement AshDurableReactor.StoreBehaviour"
           )}
        end

      {:error, reason} ->
        {:error,
         DslError.exception(
           module: module,
           path: [:durable, :store],
           message:
             "Store #{inspect(store)} could not be compiled: #{inspect(reason)}"
         )}
    end
  end

  defp return_backend_error(module, message) do
    raise DslError.exception(module: module, path: [:durable], message: message)
  end
end
