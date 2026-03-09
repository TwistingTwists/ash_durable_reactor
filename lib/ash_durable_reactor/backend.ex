defmodule AshDurableReactor.Backend do
  @moduledoc false

  alias Spark.Error.DslError

  def resolve_from_dsl_state(dsl_state) do
    resolve(%{
      store: Spark.Dsl.Extension.get_opt(dsl_state, [:durable], :store, AshDurableReactor.Store),
      store_config: Spark.Dsl.Extension.get_opt(dsl_state, [:durable], :store_config, []),
      sqlite: Spark.Dsl.Extension.get_opt(dsl_state, [:durable], :sqlite, nil),
      postgres: Spark.Dsl.Extension.get_opt(dsl_state, [:durable], :postgres, nil)
    })
  end

  def resolve_from_module(module) do
    durable_opts = %{
      store: Spark.Dsl.Extension.get_opt(module, [:durable], :store, AshDurableReactor.Store),
      store_config: Spark.Dsl.Extension.get_opt(module, [:durable], :store_config, []),
      sqlite: Spark.Dsl.Extension.get_opt(module, [:durable], :sqlite, nil),
      postgres: Spark.Dsl.Extension.get_opt(module, [:durable], :postgres, nil)
    }

    case resolve(durable_opts) do
      {:ok, resolved} -> resolved
      {:error, _reason} -> %{store: durable_opts.store, store_config: durable_opts.store_config}
    end
  end

  def resolve_from_dsl_state!(dsl_state) do
    case resolve_from_dsl_state(dsl_state) do
      {:ok, resolved} ->
        resolved

      {:error, :multiple_backends} ->
        raise dsl_error(
                dsl_state,
                "Choose only one durable backend. `sqlite` and `postgres` cannot both be configured."
              )

      {:error, :mixed_backend_and_manual_store} ->
        raise dsl_error(
                dsl_state,
                "Backend shortcuts cannot be combined with manual `store` or `store_config` options."
              )
    end
  end

  def define_modules_quoted(dsl_state) do
    case resolve_from_dsl_state(dsl_state) do
      {:ok, %{backend: {:sqlite, opts}}} ->
        AshDurableReactor.Backends.Sqlite.define_backend_quoted(opts)

      {:ok, %{backend: {:postgres, opts}}} ->
        AshDurableReactor.Backends.Postgres.define_backend_quoted(opts)

      {:ok, %{backend: nil}} ->
        nil

      {:error, _reason} ->
        nil
    end
  end

  def dsl_error(dsl_state, message, path \\ [:durable]) do
    module = Spark.Dsl.Transformer.get_persisted(dsl_state, :module)

    DslError.exception(
      module: module,
      path: path,
      message: message
    )
  end

  defp resolve(opts) do
    sqlite = normalize_backend_opts(Map.get(opts, :sqlite))
    postgres = normalize_backend_opts(Map.get(opts, :postgres))
    custom_store? = Map.get(opts, :store, AshDurableReactor.Store) != AshDurableReactor.Store
    custom_store_config? = Map.get(opts, :store_config, []) != []

    cond do
      sqlite && postgres ->
        {:error, :multiple_backends}

      (sqlite || postgres) && (custom_store? || custom_store_config?) ->
        {:error, :mixed_backend_and_manual_store}

      sqlite ->
        {:ok,
         %{
           store: AshDurableReactor.AshStore,
           store_config: AshDurableReactor.Backends.Sqlite.store_config(sqlite),
           backend: {:sqlite, sqlite}
         }}

      postgres ->
        {:ok,
         %{
           store: AshDurableReactor.AshStore,
           store_config: AshDurableReactor.Backends.Postgres.store_config(postgres),
           backend: {:postgres, postgres}
         }}

      true ->
        {:ok,
         %{
           store: Map.get(opts, :store, AshDurableReactor.Store),
           store_config: Map.get(opts, :store_config, []),
           backend: nil
         }}
    end
  end

  defp normalize_backend_opts(nil), do: nil
  defp normalize_backend_opts([]), do: nil

  defp normalize_backend_opts(opts) when is_list(opts) do
    opts
    |> Keyword.put_new_lazy(:otp_app, fn -> infer_otp_app!(Keyword.fetch!(opts, :repo)) end)
  end

  defp infer_otp_app!(repo) do
    repo
    |> Module.split()
    |> hd()
    |> Macro.underscore()
    |> String.to_atom()
  end
end
