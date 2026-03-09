defmodule AshDurableReactor.Config do
  @moduledoc """
  Internal configuration struct for a durable reactor.

  This struct is assembled from the extension DSL and then attached to the
  reactor context by `AshDurableReactor.ReactorBuilder`. It holds the runtime
  knobs that the middleware and wrapped steps need while executing a durable
  run.
  """

  defstruct store: AshDurableReactor.Store,
            store_config: [],
            persist_context: [],
            default_async?: false,
            max_concurrency: 1,
            durable_undo?: true,
            durable_compensation?: true,
            resume_strategy: :replay
end
