defmodule AshDurableReactor.StoreBehaviour do
  @moduledoc """
  Persistence contract used by the durable runtime.
  """

  @callback start_run(map) :: {:ok, map} | {:error, any}
  @callback complete_run(any, any) :: :ok
  @callback halt_run(any, any) :: :ok
  @callback fail_run(any, any) :: :ok
  @callback get_run(any) :: map | nil
  @callback list_steps(any) :: [map]
  @callback get_step(any, any) :: map | nil
  @callback record_step_running(any, any, map) :: :ok
  @callback record_step_success(any, any, any, map) :: :ok
  @callback record_step_halt(any, any, any, map) :: :ok
  @callback record_step_retry(any, any, any, map) :: :ok
  @callback record_step_error(any, any, any, map) :: :ok
  @callback record_step_compensation(any, any, atom, any) :: :ok
  @callback record_step_undo(any, any, atom, any) :: :ok
  @callback append_event(any, any, atom, any) :: :ok
  @callback resume_step(any, any, any) :: :ok | {:error, any}
  @callback reset!() :: :ok
end
