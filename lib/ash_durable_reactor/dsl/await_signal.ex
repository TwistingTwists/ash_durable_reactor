defmodule AshDurableReactor.Dsl.AwaitSignal do
  @moduledoc false

  defstruct __identifier__: nil,
            __spark_metadata__: nil,
            description: nil,
            name: nil,
            signal: nil

  @type t :: %__MODULE__{
          __identifier__: any,
          __spark_metadata__: Spark.Dsl.Entity.spark_meta(),
          description: String.t() | nil,
          name: atom,
          signal: atom
        }

  def __entity__ do
    %Spark.Dsl.Entity{
      name: :await_signal,
      describe: "Halts a durable reactor until an external signal is recorded.",
      target: __MODULE__,
      identifier: :name,
      args: [:name],
      recursive_as: :steps,
      schema: [
        name: [
          type: :atom,
          required: true,
          doc: "Unique step name."
        ],
        signal: [
          type: :atom,
          required: false,
          doc: "Signal identifier. Defaults to the step name."
        ],
        description: [
          type: :string,
          required: false
        ]
      ]
    }
  end
end
