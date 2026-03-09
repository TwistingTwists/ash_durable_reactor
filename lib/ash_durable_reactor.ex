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
        entity: AshDurableReactor.Dsl.AwaitSignal.__entity__()
      }
    ],
    transformers: [
      AshDurableReactor.Transformers.ValidateConfig,
      AshDurableReactor.Transformers.AddMiddleware,
      AshDurableReactor.Transformers.BuildReactor
    ]

  alias AshDurableReactor.{Config, ReactorBuilder, Store}
  alias Reactor.Info

  @type run_result :: {:ok, any} | {:ok, any, Reactor.t()} | {:error, any} | {:halted, Reactor.t()}

  @doc """
  Prepare a Reactor module or struct with durable wrapping.
  """
  @spec prepare_reactor(module | Reactor.t()) :: Reactor.t()
  def prepare_reactor(reactor_or_module) do
    reactor =
      case reactor_or_module do
        module when is_atom(module) -> module.reactor()
        %Reactor{} = reactor -> reactor
      end

    if Map.has_key?(reactor.context, __MODULE__) do
      reactor
    else
      config = %Config{}
      ReactorBuilder.build!(reactor, reactor.id, config)
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
  Record an external signal for an awaiting step.
  """
  @spec signal(any, any, any, module) :: :ok | {:error, any}
  def signal(run_id, signal_name, value, store \\ Store) do
    store.put_signal(run_id, signal_name, value)
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

  @doc false
  def config_from_dsl_state(dsl_state) do
    %Config{
      store: Spark.Dsl.Transformer.get_option(dsl_state, [:durable], :store) || Store,
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
end
