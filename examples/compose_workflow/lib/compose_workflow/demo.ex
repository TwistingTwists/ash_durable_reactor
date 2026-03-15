defmodule ComposeWorkflow.Demo do
  @moduledoc false

  alias AshDurableReactor.Store

  def run do
    run_id = "compose-workflow-demo"
    Store.reset!()

    IO.puts("\n=== Run 1: Fresh execution ===")

    first_result =
      AshDurableReactor.run(
        ComposeWorkflow.PipelineReactor,
        %{raw_data: %{source: "api", payload: "hello"}},
        %{},
        run_id: run_id
      )

    IO.puts("\nResult: #{inspect(first_result)}")
    IO.puts("Run state: #{inspect(Store.get_run(run_id))}")
    IO.puts("Steps: #{inspect(Store.list_steps(run_id))}")

    IO.puts("\n=== Run 2: Replay with same run_id ===")

    second_result =
      AshDurableReactor.run(
        ComposeWorkflow.PipelineReactor,
        %{raw_data: %{source: "api", payload: "hello"}},
        %{},
        run_id: run_id
      )

    IO.puts("\nResult: #{inspect(second_result)}")

    IO.puts("\n=== Comparison ===")
    IO.puts("Results match: #{first_result == second_result}")
  end
end
