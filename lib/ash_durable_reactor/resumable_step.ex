defmodule AshDurableReactor.ResumableStep do
  @moduledoc """
  Optional callback for durable steps that want custom resume behavior.
  """

  @callback resume(
              arguments :: Reactor.inputs(),
              context :: Reactor.context(),
              options :: keyword,
              persisted_step :: map
            ) :: Reactor.Step.run_result()
end
