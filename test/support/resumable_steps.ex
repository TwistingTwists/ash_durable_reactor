defmodule AshDurableReactor.TestSteps.Approval do
  use Reactor.Step

  @impl true
  def run(_arguments, _context, _options) do
    {:halt, %{awaiting: :approval}}
  end

  def resume(_arguments, _context, _options, persisted_step) do
    {:ok, persisted_step.resume_payload}
  end
end
