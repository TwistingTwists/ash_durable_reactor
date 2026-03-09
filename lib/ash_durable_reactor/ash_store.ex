defmodule AshDurableReactor.AshStore do
  @moduledoc """
  Ash-backed persistence adapter.

  Configure it with `store_config`:

  ```elixir
  durable do
    store AshDurableReactor.AshStore
    store_config [
      domain: MyApp.Durable,
      run_resource: MyApp.Durable.Run,
      step_resource: MyApp.Durable.Step,
      event_resource: MyApp.Durable.Event
    ]
  end
  ```
  """

  @behaviour AshDurableReactor.StoreBehaviour

  require Ash.Query

  @impl true
  def start_run(attrs) do
    config = config!(attrs)

    case fetch_run_record(attrs.run_id, config) do
      nil ->
        attrs
        |> Map.take([:run_id, :reactor_hash, :reactor_module, :inputs, :persisted_context])
        |> Map.put(:status, :running)
        |> create(config.run_resource, config)
        |> case do
          {:ok, run} -> {:ok, run_to_map(run)}
          {:error, reason} -> {:error, reason}
        end

      existing ->
        if existing.reactor_hash == attrs.reactor_hash do
          update(existing, %{status: :running, inputs: attrs.inputs, persisted_context: attrs.persisted_context}, config)
          {:ok, run_to_map(fetch_run_record!(attrs.run_id, config))}
        else
          {:error, {:reactor_version_mismatch, existing.reactor_hash, attrs.reactor_hash}}
        end
    end
  end

  @impl true
  def complete_run(run_id, result) do
    update_run(run_id, %{status: :succeeded, result: result})
  end

  @impl true
  def halt_run(run_id, reason) do
    update_run(run_id, %{status: :halted, halt_reason: reason})
  end

  @impl true
  def fail_run(run_id, reason) do
    update_run(run_id, %{status: :failed, error: inspect(reason)})
  end

  @impl true
  def get_run(run_id) do
    case fetch_run_record(run_id, config!()) do
      nil -> nil
      run -> run_to_map(run)
    end
  end

  @impl true
  def list_steps(run_id) do
    config = config!()
    run_id = to_string(run_id)

    config.step_resource
    |> Ash.Query.for_read(:read, %{}, domain: config.domain)
    |> Ash.Query.filter(run_id == ^run_id)
    |> Ash.read!(domain: config.domain)
    |> Enum.map(&step_to_map/1)
    |> Enum.sort_by(&{&1.step_name, &1.attempt || 0})
  end

  @impl true
  def get_step(run_id, step_name) do
    case fetch_step_record(run_id, step_name, config!()) do
      nil -> nil
      step -> step_to_map(step)
    end
  end

  @impl true
  def record_step_running(run_id, step_name, attrs) do
    upsert_step(run_id, step_name, Map.merge(attrs, %{status: :running, resume_payload: nil, resumed_at: nil}))
  end

  @impl true
  def record_step_success(run_id, step_name, output, attrs) do
    upsert_step(
      run_id,
      step_name,
      Map.merge(attrs, %{status: :succeeded, output: output, halt_payload: nil, error: nil, resume_payload: nil, resumed_at: nil})
    )
  end

  @impl true
  def record_step_halt(run_id, step_name, reason, attrs) do
    upsert_step(
      run_id,
      step_name,
      Map.merge(attrs, %{status: :halted, halt_payload: reason, output: nil, error: nil, resume_payload: nil, resumed_at: nil})
    )
  end

  @impl true
  def record_step_retry(run_id, step_name, reason, attrs) do
    upsert_step(run_id, step_name, Map.merge(attrs, %{status: :failed, error: inspect(reason), resume_payload: nil, resumed_at: nil}))
  end

  @impl true
  def record_step_error(run_id, step_name, reason, attrs) do
    upsert_step(run_id, step_name, Map.merge(attrs, %{status: :failed, error: inspect(reason), resume_payload: nil, resumed_at: nil}))
  end

  @impl true
  def record_step_compensation(run_id, step_name, status, payload) do
    upsert_step(run_id, step_name, %{status: status, compensation_payload: payload})
  end

  @impl true
  def record_step_undo(run_id, step_name, status, payload) do
    upsert_step(run_id, step_name, %{status: status, undo_payload: payload})
  end

  @impl true
  def append_event(run_id, step_name, event_type, payload) do
    config = config!()

    case Map.get(config, :event_resource) do
      nil ->
        :ok

      event_resource ->
        attrs = %{
          run_id: to_string(run_id),
          step_name: Atom.to_string(step_name),
          event_type: Atom.to_string(event_type),
          payload: payload
        }

        case create(attrs, event_resource, config) do
          {:ok, _event} -> :ok
          {:error, reason} -> {:error, reason}
        end
    end
  end

  @impl true
  def resume_step(run_id, step_name, value) do
    config = config!()

    case fetch_step_record(run_id, step_name, config) do
      nil ->
        {:error, :step_not_found}

      %{status: "halted"} = step ->
        update(step, %{resume_payload: value, resumed_at: DateTime.utc_now()}, config)
        :ok

      %{status: status} ->
        {:error, {:step_not_halted, to_existing_atom(status)}}
    end
  end

  @impl true
  def reset! do
    raise "AshStore.reset!/0 is not supported. Reset the backing data layer directly."
  end

  defp update_run(run_id, attrs) do
    config = config!()

    case fetch_run_record(run_id, config) do
      nil ->
        :ok

      run ->
        update(run, attrs, config)
        :ok
    end
  end

  defp upsert_step(run_id, step_name, attrs) do
    config = config!(attrs)

    case fetch_step_record(run_id, step_name, config) do
      nil ->
        attrs
        |> Map.put(:run_id, to_string(run_id))
        |> Map.put(:step_name, Atom.to_string(step_name))
        |> Map.put_new(:attempt, 1)
        |> create(config.step_resource, config)

      step ->
        next_attempt =
          case Map.get(attrs, :status) do
            :running -> (step.attempt || 0) + 1
            _ -> step.attempt || 1
          end

        update(step, Map.put(attrs, :attempt, next_attempt), config)
    end

    :ok
  end

  defp fetch_run_record(run_id, config) do
    run_id = to_string(run_id)

    config.run_resource
    |> Ash.Query.for_read(:read, %{}, domain: config.domain)
    |> Ash.Query.filter(run_id == ^run_id)
    |> Ash.read_one!(domain: config.domain)
  end

  defp fetch_run_record!(run_id, config) do
    fetch_run_record(run_id, config) || raise "missing run #{inspect(run_id)}"
  end

  defp fetch_step_record(run_id, step_name, config) do
    run_id = to_string(run_id)
    step_name = Atom.to_string(step_name)

    config.step_resource
    |> Ash.Query.for_read(:read, %{}, domain: config.domain)
    |> Ash.Query.filter(run_id == ^run_id and step_name == ^step_name)
    |> Ash.read_one!(domain: config.domain)
  end

  defp create(attrs, resource, config) do
    resource
    |> Ash.Changeset.for_create(:create, normalize_attrs(attrs))
    |> Ash.create(domain: config.domain)
  end

  defp update(record, attrs, config) do
    record
    |> Ash.Changeset.for_update(:update, normalize_attrs(attrs))
    |> Ash.update!(domain: config.domain)
  end

  defp normalize_attrs(attrs) do
    Map.new(attrs, fn
      {:run_id, value} -> {:run_id, to_string(value)}
      {:reactor_module, value} -> {:reactor_module, inspect(value)}
      {:step_name, value} -> {:step_name, to_string(value)}
      {:step_impl, value} -> {:step_impl, to_string(value)}
      {:status, value} when is_atom(value) -> {:status, Atom.to_string(value)}
      {:mode, value} when is_atom(value) -> {:mode, Atom.to_string(value)}
      {:config, _value} -> {:_ignored_config, nil}
      {key, value} -> {key, value}
    end)
    |> Map.delete(:_ignored_config)
  end

  defp config!(attrs \\ %{}) do
    attrs
    |> Map.get(:config)
    |> case do
      nil -> Application.fetch_env!(:ash_durable_reactor, :ash_store)
      config -> config
    end
    |> Keyword.validate!([:domain, :run_resource, :step_resource, :event_resource])
    |> Map.new()
  end

  defp run_to_map(run) do
    %{
      id: Map.get(run, :id),
      run_id: run.run_id,
      reactor_hash: run.reactor_hash,
      reactor_module: run.reactor_module,
      status: to_existing_atom(run.status),
      inputs: run.inputs,
      persisted_context: run.persisted_context,
      result: run.result,
      error: run.error,
      halt_reason: run.halt_reason,
      attempt: run.attempt,
      inserted_at: Map.get(run, :inserted_at),
      updated_at: Map.get(run, :updated_at),
      completed_at: Map.get(run, :completed_at)
    }
  end

  defp step_to_map(step) do
    %{
      id: Map.get(step, :id),
      run_id: step.run_id,
      step_name: String.to_atom(step.step_name),
      step_impl: step.step_impl,
      step_hash: step.step_hash,
      status: to_existing_atom(step.status),
      attempt: step.attempt,
      mode: to_existing_atom(step.mode),
      inputs: step.inputs,
      output: step.output,
      error: step.error,
      halt_payload: step.halt_payload,
      resume_payload: step.resume_payload,
      resumed_at: Map.get(step, :resumed_at),
      compensation_payload: step.compensation_payload,
      undo_payload: step.undo_payload,
      inserted_at: Map.get(step, :inserted_at),
      updated_at: Map.get(step, :updated_at),
      completed_at: Map.get(step, :completed_at),
      started_at: Map.get(step, :started_at)
    }
  end

  defp to_existing_atom(nil), do: nil
  defp to_existing_atom(value) when is_atom(value), do: value
  defp to_existing_atom(value), do: String.to_existing_atom(value)
end
