defmodule AshDurableReactor.Config do
  @moduledoc false

  defstruct store: AshDurableReactor.Store,
            store_config: [],
            persist_context: [],
            default_async?: false,
            max_concurrency: 1,
            durable_undo?: true,
            durable_compensation?: true,
            resume_strategy: :replay
end
