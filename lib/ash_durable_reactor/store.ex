defmodule AshDurableReactor.Store do
  @moduledoc """
  ETS-backed persistence adapter used for tests and examples.
  """

  use GenServer

  @behaviour AshDurableReactor.StoreBehaviour

  @runs :ash_durable_reactor_runs
  @steps :ash_durable_reactor_steps
  @events :ash_durable_reactor_events

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(state) do
    new_table(@runs, [:named_table, :set, :public])
    new_table(@steps, [:named_table, :set, :public])
    new_table(@events, [:named_table, :bag, :public])
    {:ok, state}
  end

  @impl true
  def start_run(attrs) do
    run_id = Map.fetch!(attrs, :run_id)

    case get_run(run_id) do
      nil ->
        run =
          attrs
          |> Map.put(:status, :running)
          |> Map.put_new(:attempt, 1)
          |> Map.put_new(:inserted_at, DateTime.utc_now())
          |> Map.put(:updated_at, DateTime.utc_now())

        true = :ets.insert(@runs, {run_id, run})
        {:ok, run}

      existing ->
        case existing[:reactor_hash] == attrs[:reactor_hash] do
          true ->
            run =
              existing
              |> Map.merge(Map.take(attrs, [:inputs, :persisted_context]))
              |> Map.put(:status, :running)
              |> Map.update(:attempt, 1, &(&1 + 1))
              |> Map.put(:updated_at, DateTime.utc_now())

            true = :ets.insert(@runs, {run_id, run})
            {:ok, run}

          false ->
            {:error, {:reactor_version_mismatch, existing[:reactor_hash], attrs[:reactor_hash]}}
        end
    end
  end

  @impl true
  def complete_run(run_id, result) do
    update_run(run_id, fn run ->
      run
      |> Map.put(:status, :succeeded)
      |> Map.put(:result, result)
      |> Map.put(:completed_at, DateTime.utc_now())
      |> Map.put(:updated_at, DateTime.utc_now())
    end)
  end

  @impl true
  def halt_run(run_id, reason) do
    update_run(run_id, fn run ->
      run
      |> Map.put(:status, :halted)
      |> Map.put(:halt_reason, reason)
      |> Map.put(:updated_at, DateTime.utc_now())
    end)
  end

  @impl true
  def fail_run(run_id, reason) do
    update_run(run_id, fn run ->
      run
      |> Map.put(:status, :failed)
      |> Map.put(:error, reason)
      |> Map.put(:completed_at, DateTime.utc_now())
      |> Map.put(:updated_at, DateTime.utc_now())
    end)
  end

  @impl true
  def get_run(run_id) do
    case :ets.lookup(@runs, run_id) do
      [{^run_id, run}] -> run
      [] -> nil
    end
  end

  @impl true
  def list_steps(run_id) do
    @steps
    |> :ets.tab2list()
    |> Enum.filter(fn {{stored_run_id, _step_name}, _step} -> stored_run_id == run_id end)
    |> Enum.map(fn {_key, step} -> step end)
    |> Enum.sort_by(&{&1.step_name, &1.attempt})
  end

  @impl true
  def get_step(run_id, step_name) do
    key = {run_id, step_name}

    case :ets.lookup(@steps, key) do
      [{^key, step}] -> step
      [] -> nil
    end
  end

  @impl true
  def record_step_running(run_id, step_name, attrs) do
    upsert_step(run_id, step_name, fn step ->
      step
      |> Map.merge(Map.take(attrs, [:inputs, :step_impl, :step_hash, :mode]))
      |> Map.put(:status, :running)
      |> clear_resume_fields()
      |> Map.update(:attempt, 1, &(&1 + 1))
      |> Map.put(:started_at, DateTime.utc_now())
      |> Map.put(:updated_at, DateTime.utc_now())
    end)
  end

  @impl true
  def record_step_success(run_id, step_name, output, attrs) do
    upsert_step(run_id, step_name, fn step ->
      step
      |> Map.merge(Map.take(attrs, [:inputs, :step_impl, :step_hash, :mode]))
      |> Map.put(:status, :succeeded)
      |> Map.put(:output, output)
      |> Map.put(:halt_payload, nil)
      |> Map.put(:error, nil)
      |> clear_resume_fields()
      |> Map.put(:completed_at, DateTime.utc_now())
      |> Map.put(:updated_at, DateTime.utc_now())
    end)
  end

  @impl true
  def record_step_halt(run_id, step_name, reason, attrs) do
    upsert_step(run_id, step_name, fn step ->
      step
      |> Map.merge(Map.take(attrs, [:inputs, :step_impl, :step_hash, :mode]))
      |> Map.put(:status, :halted)
      |> Map.put(:halt_payload, reason)
      |> Map.put(:output, nil)
      |> Map.put(:error, nil)
      |> clear_resume_fields()
      |> Map.put(:updated_at, DateTime.utc_now())
    end)
  end

  @impl true
  def record_step_retry(run_id, step_name, reason, attrs) do
    upsert_step(run_id, step_name, fn step ->
      step
      |> Map.merge(Map.take(attrs, [:inputs, :step_impl, :step_hash, :mode]))
      |> Map.put(:status, :failed)
      |> Map.put(:error, reason)
      |> clear_resume_fields()
      |> Map.put(:updated_at, DateTime.utc_now())
    end)
  end

  @impl true
  def record_step_error(run_id, step_name, reason, attrs) do
    upsert_step(run_id, step_name, fn step ->
      step
      |> Map.merge(Map.take(attrs, [:inputs, :step_impl, :step_hash, :mode]))
      |> Map.put(:status, :failed)
      |> Map.put(:error, reason)
      |> clear_resume_fields()
      |> Map.put(:completed_at, DateTime.utc_now())
      |> Map.put(:updated_at, DateTime.utc_now())
    end)
  end

  @impl true
  def record_step_compensation(run_id, step_name, status, payload) do
    upsert_step(run_id, step_name, fn step ->
      step
      |> Map.put(:status, status)
      |> Map.put(:compensation_payload, payload)
      |> Map.put(:updated_at, DateTime.utc_now())
    end)
  end

  @impl true
  def record_step_undo(run_id, step_name, status, payload) do
    upsert_step(run_id, step_name, fn step ->
      step
      |> Map.put(:status, status)
      |> Map.put(:undo_payload, payload)
      |> Map.put(:updated_at, DateTime.utc_now())
    end)
  end

  @impl true
  def append_event(run_id, step_name, event_type, payload) do
    id = :erlang.unique_integer([:positive, :monotonic])
    event = %{id: id, run_id: run_id, step_name: step_name, event_type: event_type, payload: payload}
    true = :ets.insert(@events, {run_id, event})
    :ok
  end

  @impl true
  def resume_step(run_id, step_name, value) do
    case get_step(run_id, step_name) do
      nil ->
        {:error, :step_not_found}

      %{status: :halted} ->
        upsert_step(run_id, step_name, fn step ->
          step
          |> Map.put(:resume_payload, value)
          |> Map.put(:resumed_at, DateTime.utc_now())
          |> Map.put(:updated_at, DateTime.utc_now())
        end)

      %{status: status} ->
        {:error, {:step_not_halted, status}}
    end
  end

  @impl true
  def reset! do
    for table <- [@runs, @steps, @events] do
      :ets.delete_all_objects(table)
    end

    :ok
  end

  defp update_run(run_id, fun) do
    run =
      run_id
      |> get_run()
      |> then(fn
        nil -> %{run_id: run_id}
        run -> run
      end)
      |> fun.()

    true = :ets.insert(@runs, {run_id, run})
    :ok
  end

  defp upsert_step(run_id, step_name, fun) do
    existing =
      get_step(run_id, step_name) ||
        %{
          run_id: run_id,
          step_name: step_name,
          attempt: 0
        }

    case fun.(existing) do
      {:error, _reason} = error ->
        error

      updated ->
        true = :ets.insert(@steps, {{run_id, step_name}, updated})
        :ok
    end
  end

  defp new_table(name, options) do
    case :ets.whereis(name) do
      :undefined -> :ets.new(name, options)
      _tid -> name
    end
  end

  defp clear_resume_fields(step) do
    step
    |> Map.put(:resume_payload, nil)
    |> Map.put(:resumed_at, nil)
  end
end
