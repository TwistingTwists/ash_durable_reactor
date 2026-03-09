defmodule AshDurableReactor do
  @moduledoc """
  Durable execution support for Reactor.

  The extension wraps each step with a persistence-aware delegator, stores run
  and step state in a pluggable store, and adds a small durable DSL surface for
  halt/resume workflows.
  """

  use Spark.Dsl.Extension,
    sections: [AshDurableReactor.Dsl.Durable.section()],
    dsl_patches: [
      %Spark.Dsl.Patch.AddEntity{
        section_path: [:reactor],
        entity: AshDurableReactor.Dsl.AwaitResume.__entity__()
      }
    ],
    transformers: [
      AshDurableReactor.Transformers.ValidateConfig,
      AshDurableReactor.Transformers.AddMiddleware,
      AshDurableReactor.Transformers.BuildReactor
    ],
    verifiers: [AshDurableReactor.Verifiers.ValidateBackends]

  alias AshDurableReactor.{Config, ReactorBuilder, Store}
  alias Reactor.Info

  @type run_result :: {:ok, any} | {:ok, any, Reactor.t()} | {:error, any} | {:halted, Reactor.t()}

  @doc """
  Prepare a Reactor module or struct with durable wrapping.
  """
  @spec prepare_reactor(module | Reactor.t()) :: Reactor.t()
  def prepare_reactor(reactor_or_module) do
    {reactor, config, reactor_module} =
      case reactor_or_module do
        module when is_atom(module) ->
          {Info.to_struct!(module), config_from_module(module), module}

        %Reactor{} = reactor ->
          {reactor, %Config{}, reactor.id}
      end

    if Map.has_key?(reactor.context, __MODULE__) do
      reactor
    else
      ReactorBuilder.build!(reactor, reactor_module, config)
    end
  end

  @doc """
  Run a durable reactor, defaulting to synchronous execution.
  """
  @spec run(module | Reactor.t(), Reactor.inputs(), Reactor.context_arg(), keyword) :: run_result
  def run(reactor, inputs \\ %{}, context \\ %{}, options \\ []) do
    reactor
    |> prepare_reactor()
    |> Reactor.run(inputs, context, Keyword.put_new(options, :async?, false))
  end

  @doc """
  Mark a halted step as resumable on the next replay.
  """
  @spec resume_step(any, any, any, module) :: :ok | {:error, any}
  def resume_step(run_id, step_name, value, store \\ Store) do
    store.resume_step(run_id, step_name, value)
  end

  @doc """
  Fetch persisted run state.
  """
  @spec get_run(any, module) :: map | nil
  def get_run(run_id, store \\ Store), do: store.get_run(run_id)

  @doc """
  Fetch persisted step state.
  """
  @spec get_step(any, any, module) :: map | nil
  def get_step(run_id, step_name, store \\ Store), do: store.get_step(run_id, step_name)

  @doc """
  List persisted steps for a run.
  """
  @spec list_steps(any, module) :: [map]
  def list_steps(run_id, store \\ Store), do: store.list_steps(run_id)

  @doc """
  Fetch the persisted state for the currently executing durable step.
  """
  @spec current_step(Reactor.context()) :: map | nil
  def current_step(context) when is_map(context) do
    get_in(context, [__MODULE__, :current_step])
  end

  @doc """
  Fetch the persisted resume payload for the currently executing durable step.
  """
  @spec resume_payload(Reactor.context()) :: any
  def resume_payload(context) when is_map(context) do
    context
    |> current_step()
    |> case do
      nil -> nil
      step -> Map.get(step, :resume_payload)
    end
  end

  @doc false
  def config_from_dsl_state(dsl_state) do
    %{store: store, store_config: store_config} = AshDurableReactor.Backend.resolve_from_dsl_state!(dsl_state)

    %Config{
      store: store,
      store_config: store_config,
      persist_context:
        Spark.Dsl.Transformer.get_option(dsl_state, [:durable], :persist_context) || [],
      default_async?:
        Spark.Dsl.Transformer.get_option(dsl_state, [:durable], :default_async?) || false,
      max_concurrency:
        Spark.Dsl.Transformer.get_option(dsl_state, [:durable], :max_concurrency) || 1,
      durable_undo?:
        Spark.Dsl.Transformer.get_option(dsl_state, [:durable], :durable_undo?) != false,
      durable_compensation?:
        Spark.Dsl.Transformer.get_option(dsl_state, [:durable], :durable_compensation?) != false,
      resume_strategy:
        Spark.Dsl.Transformer.get_option(dsl_state, [:durable], :resume_strategy) || :replay
    }
  end

  defp config_from_module(module) do
    %{store: store, store_config: store_config} = AshDurableReactor.Backend.resolve_from_module(module)

    %Config{
      store: store,
      store_config: store_config,
      persist_context: Spark.Dsl.Extension.get_opt(module, [:durable], :persist_context, []),
      default_async?: Spark.Dsl.Extension.get_opt(module, [:durable], :default_async?, false),
      max_concurrency: Spark.Dsl.Extension.get_opt(module, [:durable], :max_concurrency, 1),
      durable_undo?: Spark.Dsl.Extension.get_opt(module, [:durable], :durable_undo?, true),
      durable_compensation?:
        Spark.Dsl.Extension.get_opt(module, [:durable], :durable_compensation?, true),
      resume_strategy: Spark.Dsl.Extension.get_opt(module, [:durable], :resume_strategy, :replay)
    }
  end
end
