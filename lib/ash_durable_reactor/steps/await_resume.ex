defmodule AshDurableReactor.Steps.AwaitResume do
  @moduledoc """
  Halt until the step is explicitly resumed.
  """

  use Reactor.Step
  @behaviour AshDurableReactor.ResumableStep

  @impl true
  def run(_arguments, _context, options) do
    {:halt, %{awaiting: Keyword.fetch!(options, :step_name)}}
  end

  @impl AshDurableReactor.ResumableStep
  def resume(_arguments, context, _options, persisted_step) do
    {:ok, persisted_step.resume_payload || AshDurableReactor.resume_payload(context)}
  end

  @impl true
  def async?(_), do: false
end
