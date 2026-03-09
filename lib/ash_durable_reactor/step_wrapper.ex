defmodule AshDurableReactor.StepWrapper do
  @moduledoc """
  Persistence-aware wrapper around normal Reactor steps.

  Every durable step runs through this wrapper. It is responsible for:

  - loading any persisted checkpoint for the current `run_id + step_name`
  - returning stored outputs for replayable successful steps
  - halting resumable steps until a resume payload is written
  - dispatching to a step's custom `resume/4` callback when present
  - persisting run, halt, retry, compensation, and undo outcomes back to the store

  This module is the main execution boundary where Reactor step semantics are
  translated into durable checkpoints.
  """

  use Reactor.Step

  alias AshDurableReactor.ReactorBuilder

  @impl true
  def run(arguments, context, options) do
    original_step = Keyword.fetch!(options, :original_step)
    config = Keyword.fetch!(options, :config)
    store = config.store
    run_id = context.run_id
    mode = Keyword.fetch!(options, :mode)
    persisted_step = store.get_step(run_id, original_step.name)

    case replay_result(persisted_step, mode) do
      {:ok, output} ->
        {:ok, output}

      {:halted, reason} ->
        {:halt, reason}

      {:resume, step_state} ->
        attrs = step_attrs(arguments, original_step, mode, Keyword.fetch!(options, :config))
        :ok = store.record_step_running(run_id, original_step.name, attrs)

        original_step
        |> resume_step(arguments, with_current_step(context, step_state))
        |> handle_run_result(store, run_id, original_step, attrs, context, options)

      :miss ->
        attrs = step_attrs(arguments, original_step, mode, Keyword.fetch!(options, :config))
        :ok = store.record_step_running(run_id, original_step.name, attrs)

        original_step
        |> Reactor.Step.run(arguments, context)
        |> handle_run_result(store, run_id, original_step, attrs, context, options)
    end
  end

  @impl true
  def compensate(reason, arguments, context, options) do
    original_step = Keyword.fetch!(options, :original_step)
    store = Keyword.fetch!(options, :config).store
    run_id = context.run_id

    result = Reactor.Step.compensate(original_step, reason, arguments, context)

    case result do
      {:continue, value} ->
        :ok = store.record_step_compensation(run_id, original_step.name, :succeeded, value)
        :ok = store.record_step_success(run_id, original_step.name, value, %{})
        {:continue, value}

      :ok ->
        :ok = store.record_step_compensation(run_id, original_step.name, :compensated, reason)
        :ok

      :retry ->
        :ok = store.record_step_compensation(run_id, original_step.name, :retrying, reason)
        :retry

      {:retry, retry_reason} ->
        :ok = store.record_step_compensation(run_id, original_step.name, :retrying, retry_reason)
        {:retry, retry_reason}

      {:error, error} ->
        :ok = store.record_step_compensation(run_id, original_step.name, :failed, error)
        {:error, error}
    end
  end

  @impl true
  def undo(value, arguments, context, options) do
    original_step = Keyword.fetch!(options, :original_step)
    store = Keyword.fetch!(options, :config).store
    run_id = context.run_id

    result = Reactor.Step.undo(original_step, value, arguments, context)

    case result do
      :ok ->
        :ok = store.record_step_undo(run_id, original_step.name, :undone, value)
        :ok

      :retry ->
        :ok = store.record_step_undo(run_id, original_step.name, :undo_retry, value)
        :retry

      {:retry, reason} ->
        :ok = store.record_step_undo(run_id, original_step.name, :undo_retry, reason)
        {:retry, reason}

      {:error, error} ->
        :ok = store.record_step_undo(run_id, original_step.name, :undo_failed, error)
        {:error, error}
    end
  end

  @impl true
  def can?(%{impl: {__MODULE__, options}} = _step, capability) do
    original_step = Keyword.fetch!(options, :original_step)
    Reactor.Step.can?(original_step, capability)
  end

  @impl true
  def async?(_step), do: false

  @impl true
  def nested_steps(options) do
    options
    |> Keyword.fetch!(:original_step)
    |> Reactor.Step.nested_steps()
  end

  @impl true
  def backoff(reason, arguments, context, options) do
    options
    |> Keyword.fetch!(:original_step)
    |> Reactor.Step.backoff(reason, arguments, context)
  end

  defp replay_result(%{status: :succeeded, output: output}, mode)
       when mode in [:replayable, :resumable, :side_effect_once],
       do: {:ok, output}

  defp replay_result(%{status: :halted, halt_payload: reason, resume_payload: nil}, :resumable),
    do: {:halted, reason}

  defp replay_result(%{status: :halted, resume_payload: _payload} = persisted_step, :resumable),
    do: {:resume, persisted_step}

  defp replay_result(_persisted_step, _mode), do: :miss

  defp handle_run_result({:ok, value}, store, run_id, original_step, attrs, _context, _options) do
    :ok = store.record_step_success(run_id, original_step.name, value, attrs)
    {:ok, value}
  end

  defp handle_run_result({:ok, value, steps}, store, run_id, original_step, attrs, context, _options)
       when is_list(steps) do
    durable_context = context[AshDurableReactor]
    wrapped_steps = Enum.map(steps, &ReactorBuilder.wrap_dynamic_step(&1, durable_context))
    :ok = store.record_step_success(run_id, original_step.name, value, Map.put(attrs, :dynamic_steps, length(steps)))
    {:ok, value, wrapped_steps}
  end

  defp handle_run_result({:halt, reason}, store, run_id, original_step, attrs, _context, _options) do
    :ok = store.record_step_halt(run_id, original_step.name, reason, attrs)
    {:halt, reason}
  end

  defp handle_run_result(:retry, store, run_id, original_step, attrs, _context, _options) do
    :ok = store.record_step_retry(run_id, original_step.name, nil, attrs)
    :retry
  end

  defp handle_run_result({:retry, reason}, store, run_id, original_step, attrs, _context, _options) do
    :ok = store.record_step_retry(run_id, original_step.name, reason, attrs)
    {:retry, reason}
  end

  defp handle_run_result({:error, reason}, store, run_id, original_step, attrs, _context, _options) do
    :ok = store.record_step_error(run_id, original_step.name, reason, attrs)
    {:error, reason}
  end

  defp step_attrs(arguments, original_step, mode, config) do
    %{
      config: config.store_config,
      inputs: arguments,
      step_impl: inspect(original_step.impl),
      step_hash: :erlang.phash2({original_step.name, original_step.impl, original_step.arguments}),
      mode: mode
    }
  end

  defp resume_step(original_step, arguments, context) do
    {module, options} = module_and_options(original_step)
    persisted_step = AshDurableReactor.current_step(context)

    if function_exported?(module, :resume, 4) do
      module.resume(arguments, context, options, persisted_step)
    else
      Reactor.Step.run(original_step, arguments, context)
    end
  end

  defp module_and_options(%{impl: {module, options}}), do: {module, options}
  defp module_and_options(%{impl: module}), do: {module, []}

  defp with_current_step(context, persisted_step) do
    put_in(context, [AshDurableReactor, :current_step], persisted_step)
  end
end
