defmodule AshDurableReactor.Transformers.BuildReactor do
  @moduledoc false

  use Spark.Dsl.Transformer

  @impl true
  def after?(Reactor.Dsl.Transformer), do: true
  def after?(_), do: false

  @impl true
  def transform(dsl_state) do
    module = Spark.Dsl.Transformer.get_persisted(dsl_state, :module)
    config = AshDurableReactor.config_from_dsl_state(dsl_state)

    with {:ok, reactor} <- Reactor.Info.to_struct(dsl_state),
         {:ok, reactor} <- AshDurableReactor.ReactorBuilder.build(reactor, module, config) do
      dsl_state =
        Spark.Dsl.Transformer.eval(
          dsl_state,
          [],
          quote do
            @doc false
            @spec reactor :: Reactor.t()
            def reactor, do: unquote(Macro.escape(reactor))
          end
        )

      {:ok, dsl_state}
    end
  end
end
