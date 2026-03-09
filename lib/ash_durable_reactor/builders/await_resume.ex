defimpl Reactor.Dsl.Build, for: AshDurableReactor.Dsl.AwaitResume do
  @moduledoc false

  alias Reactor.Builder

  @impl true
  def build(step, reactor) do
    Builder.add_step(
      reactor,
      step.name,
      {AshDurableReactor.Steps.AwaitResume, step_name: step.name},
      [],
      async?: false,
      description: step.description,
      ref: :step_name
    )
  end

  @impl true
  def verify(_, _), do: :ok
end
