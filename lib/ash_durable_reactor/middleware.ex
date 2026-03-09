defmodule AshDurableReactor.Middleware do
  @moduledoc """
  Reactor middleware responsible for run-level durable state.

  The middleware owns lifecycle concerns that apply to the entire run rather
  than to a single step:

  - create or load the durable run record at startup
  - persist the final run outcome on halt, success, or failure
  - append lightweight lifecycle events for observability

  Step-level checkpointing is handled separately by
  `AshDurableReactor.StepWrapper`.
  """

  use Reactor.Middleware

  @impl true
  def init(context) do
    durable = Map.fetch!(context, AshDurableReactor)
    config = durable.config
    run_id = context.run_id
    store = config.store
    inputs = get_in(context, [:private, :inputs]) || %{}

    attrs = %{
      run_id: run_id,
      reactor_hash: durable.reactor_hash,
      reactor_module: durable.reactor_module,
      config: config.store_config,
      inputs: inputs
    }

    case store.start_run(attrs) do
      {:ok, _run} ->
        {:ok, context}

      {:error, reason} ->
        {:error, ArgumentError.exception("unable to start durable run: #{inspect(reason)}")}
    end
  end

  @impl true
  def halt(context) do
    store = context[AshDurableReactor].config.store
    run_id = context.run_id

    reason =
      run_id
      |> store.list_steps()
      |> Enum.reverse()
      |> Enum.find_value(fn
        %{status: :halted, step_name: step_name, halt_payload: payload} ->
          %{step: step_name, payload: payload}

        _step ->
          nil
      end)

    :ok = store.halt_run(run_id, reason || %{step: nil})
    {:ok, context}
  end

  @impl true
  def complete(result, context) do
    :ok = context[AshDurableReactor].config.store.complete_run(context.run_id, result)
    {:ok, result}
  end

  @impl true
  def error(error, context) do
    :ok = context[AshDurableReactor].config.store.fail_run(context.run_id, error)
    :ok
  end

  @impl true
  def event(event, step, context) do
    :ok =
      context[AshDurableReactor].config.store.append_event(
        context.run_id,
        step.name,
        classify_event(event),
        normalize_event_payload(event)
      )
  end

  defp classify_event({name, _payload}) when is_atom(name), do: name
  defp classify_event(name) when is_atom(name), do: name
  defp classify_event(_), do: :unknown

  defp normalize_event_payload(payload) when is_map(payload), do: payload
  defp normalize_event_payload(payload), do: %{event: inspect(payload)}
end
