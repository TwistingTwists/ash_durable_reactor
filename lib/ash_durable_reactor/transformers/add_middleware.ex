defmodule AshDurableReactor.Transformers.AddMiddleware do
  @moduledoc """
  Spark transformer that injects the durable middleware automatically.

  This keeps durable setup declarative: users opt into the extension and the
  required middleware is added for them instead of relying on manual reactor
  configuration.
  """

  use Spark.Dsl.Transformer

  @impl true
  def before?(Reactor.Dsl.Transformer), do: true
  def before?(_), do: false

  @impl true
  def transform(dsl_state) do
    with {:ok, middleware} <-
           Spark.Dsl.Transformer.build_entity(Reactor.Dsl, [:reactor, :middlewares], :middleware,
             module: AshDurableReactor.Middleware
           ) do
      {:ok, Spark.Dsl.Transformer.add_entity(dsl_state, [:reactor, :middlewares], middleware)}
    end
  end
end
