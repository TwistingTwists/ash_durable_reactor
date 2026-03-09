defmodule AshDurableReactor.Dsl.AwaitResume do
  @moduledoc false

  defstruct __identifier__: nil,
            __spark_metadata__: nil,
            description: nil,
            name: nil

  @type t :: %__MODULE__{
          __identifier__: any,
          __spark_metadata__: Spark.Dsl.Entity.spark_meta(),
          description: String.t() | nil,
          name: atom
        }

  def __entity__ do
    %Spark.Dsl.Entity{
      name: :await_resume,
      describe: "Halts a durable reactor until the step is explicitly resumed.",
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
        description: [
          type: :string,
          required: false
        ]
      ]
    }
  end
end
