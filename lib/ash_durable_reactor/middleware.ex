defmodule AshDurableReactor.Middleware do
  @moduledoc false

  use Reactor.Middleware

  alias AshDurableReactor.{Config, Store}

  @impl true
  def init(context) do
    durable = Map.fetch!(context, AshDurableReactor)
    config = durable.config
    run_id = context.run_id
    store = config.store
    inputs = get_in(context, [:private, :inputs]) || %{}
    persisted_context = Map.take(context, config.persist_context)

    attrs = %{
      run_id: run_id,
      reactor_hash: durable.reactor_hash,
      reactor_module: durable.reactor_module,
      inputs: inputs,
      persisted_context: persisted_context
    }

    case store.start_run(attrs) do
      {:ok, _run} ->
        {:ok, put_in(context, [AshDurableReactor, :persisted_context], persisted_context)}

      {:error, reason} ->
        {:error, ArgumentError.exception("unable to start durable run: #{inspect(reason)}")}
    end
  end

  @impl true
  def halt(context) do
    store = context[AshDurableReactor].config.store
    run_id = context.run_id
    current_step = get_in(context, [:current_step, :name])
    reason = current_step && store.get_step(run_id, current_step) && store.get_step(run_id, current_step).halt_payload
    :ok = store.halt_run(run_id, reason || %{step: current_step})
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
    :ok = context[AshDurableReactor].config.store.append_event(context.run_id, step.name, classify_event(event), event)
  end

  defp classify_event({name, _payload}) when is_atom(name), do: name
  defp classify_event(name) when is_atom(name), do: name
  defp classify_event(_), do: :unknown
end
