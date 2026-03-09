defmodule AshDurableReactor.Verifiers.ValidateBackends do
  @moduledoc """
  Verifies that durable backend selection is unambiguous.
  """

  use Spark.Dsl.Verifier

  def verify(dsl_state) do
    sqlite = Spark.Dsl.Extension.get_opt(dsl_state, [:durable], :sqlite, nil)
    postgres = Spark.Dsl.Extension.get_opt(dsl_state, [:durable], :postgres, nil)
    store = Spark.Dsl.Extension.get_opt(dsl_state, [:durable], :store, AshDurableReactor.Store)
    store_config = Spark.Dsl.Extension.get_opt(dsl_state, [:durable], :store_config, [])

    cond do
      present?(sqlite) && present?(postgres) ->
        {:error,
         AshDurableReactor.Backend.dsl_error(
           dsl_state,
           "Choose only one durable backend. `sqlite` and `postgres` cannot both be configured."
         )}

      (present?(sqlite) || present?(postgres)) &&
          (store != AshDurableReactor.Store || store_config != []) ->
        {:error,
         AshDurableReactor.Backend.dsl_error(
           dsl_state,
           "Backend shortcuts cannot be combined with manual `store` or `store_config` options."
         )}

      true ->
        :ok
    end
  end

  defp present?(nil), do: false
  defp present?([]), do: false
  defp present?(_value), do: true
end
