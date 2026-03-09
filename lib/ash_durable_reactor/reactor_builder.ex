defmodule AshDurableReactor.ReactorBuilder do
  @moduledoc """
  Prepares a plain Reactor struct for durable execution.

  The builder is the point where the extension becomes concrete runtime
  behavior. It wraps every step with `AshDurableReactor.StepWrapper`, injects
  the durable middleware, computes a stable reactor hash, and replans the graph
  after those transformations.

  It also infers step durability mode:

  - `:replayable` for normal checkpointed steps
  - `:resumable` for steps whose implementation exports `resume/4`
  """

  alias AshDurableReactor.{Config, Middleware, StepWrapper}
  alias Reactor.Planner

  @spec build!(Reactor.t(), module | any, Config.t()) :: Reactor.t()
  def build!(reactor, reactor_module, config) do
    case build(reactor, reactor_module, config) do
      {:ok, reactor} -> reactor
      {:error, reason} -> raise reason
    end
  end

  @spec build(Reactor.t(), module | any, Config.t()) :: {:ok, Reactor.t()} | {:error, any}
  def build(reactor, reactor_module, %Config{} = config) do
    wrapped_steps =
      Enum.map(reactor.steps, fn step ->
        wrap_step(step, reactor_module, config)
      end)

    durable_context = %{
      config: config,
      reactor_module: reactor_module,
      reactor_hash: reactor_hash(reactor, wrapped_steps)
    }

    reactor =
      reactor
      |> Map.put(:steps, wrapped_steps)
      |> Map.put(:plan, nil)
      |> Map.put(:context, Map.put(reactor.context, AshDurableReactor, durable_context))
      |> ensure_middleware(Middleware)

    Planner.plan(reactor)
  end

  @spec wrap_dynamic_step(Reactor.Step.t(), map, keyword) :: Reactor.Step.t()
  def wrap_dynamic_step(step, durable_context, opts \\ []) do
    wrap_step(step, durable_context.reactor_module, durable_context.config, Keyword.get(opts, :dynamic?, true))
  end

  defp wrap_step(step, reactor_module, %Config{} = config, dynamic? \\ false) do
    if wrapped_step?(step) do
      step
    else
      mode = durable_mode(step)
      original_async? = step.async?

      %{
        step
        | impl:
            {StepWrapper,
             original_step: step,
             reactor_module: reactor_module,
             config: config,
             mode: mode,
             original_async?: original_async?,
             dynamic?: dynamic?},
          async?: config.default_async?
      }
    end
  end

  defp wrapped_step?(%{impl: {StepWrapper, _opts}}), do: true
  defp wrapped_step?(_step), do: false

  defp ensure_middleware(reactor, middleware) do
    if middleware in reactor.middleware do
      reactor
    else
      %{reactor | middleware: reactor.middleware ++ [middleware]}
    end
  end

  defp reactor_hash(reactor, wrapped_steps) do
    payload =
      wrapped_steps
      |> Enum.map(fn step ->
        {step.name, inspect(step.impl), step.arguments |> Enum.map(&inspect/1)}
      end)
      |> then(&{reactor.id, reactor.return, &1})

    :erlang.phash2(payload)
  end

  defp durable_mode(step) do
    get_in(step.context, [:durable, :mode]) || if(resumable_step?(step), do: :resumable, else: :replayable)
  end

  defp resumable_step?(%{impl: {module, _options}}) when is_atom(module) do
    function_exported?(module, :resume, 4)
  end

  defp resumable_step?(%{impl: module}) when is_atom(module) do
    function_exported?(module, :resume, 4)
  end

  defp resumable_step?(_step), do: false
end
