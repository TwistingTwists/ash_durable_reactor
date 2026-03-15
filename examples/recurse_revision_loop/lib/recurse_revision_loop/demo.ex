defmodule RecurseRevisionLoop.Demo do
  @moduledoc false

  alias AshDurableReactor.Store

  def run do
    run_id = "revision-loop-demo"
    Store.reset!()

    initial_draft = %{content: "draft", revision_number: 0, approved: false}

    IO.puts("=== First run: execute all iterations ===")
    IO.puts("Initial: #{inspect(initial_draft)}")
    IO.puts("")

    {:ok, result} =
      AshDurableReactor.run(
        RecurseRevisionLoop.LoopReactor,
        %{draft: initial_draft},
        %{},
        run_id: run_id,
        async?: false
      )

    IO.puts("")
    IO.puts("Result: #{inspect(result.draft)}")
    IO.puts("Iterations: #{result.draft.revision_number}")
    IO.puts("Approved: #{result.draft.approved}")

    steps = AshDurableReactor.list_steps(run_id)
    IO.puts("Persisted steps: #{length(steps)}")

    IO.puts("")
    IO.puts("=== Second run (same run_id): replay from store ===")
    IO.puts("")

    {:ok, replayed} =
      AshDurableReactor.run(
        RecurseRevisionLoop.LoopReactor,
        %{draft: initial_draft},
        %{},
        run_id: run_id,
        async?: false
      )

    IO.puts("Replayed result: #{inspect(replayed.draft)}")
    IO.puts("Match: #{replayed == result}")

    IO.puts("")
    IO.puts("Done.")
  end
end
