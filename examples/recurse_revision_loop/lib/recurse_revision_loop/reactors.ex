defmodule RecurseRevisionLoop.Steps.Revise do
  @moduledoc false
  use Reactor.Step

  @impl true
  def run(%{draft: draft}, _context, _options) do
    revision = Map.get(draft, :revision_number, 0) + 1
    content = Map.get(draft, :content, "") <> " [rev#{revision}]"
    approved = revision >= 3

    IO.puts("  revision ##{revision}: approved=#{approved}")

    {:ok, %{content: content, revision_number: revision, approved: approved}}
  end
end

defmodule RecurseRevisionLoop.RevisionReactor do
  @moduledoc """
  Inner reactor that performs a single revision pass.

  Takes a `draft` input, revises it, and wraps the result back into
  `%{draft: result}` so the recurse loop can feed it into the next iteration.
  """
  use Reactor, extensions: [AshDurableReactor]

  input :draft

  step :revise, RecurseRevisionLoop.Steps.Revise do
    argument :draft, input(:draft)
  end

  step :wrap_for_recurse do
    argument :result, result(:revise)
    run fn %{result: result}, _ctx -> {:ok, %{draft: result}} end
  end

  return :wrap_for_recurse
end

defmodule RecurseRevisionLoop.LoopReactor do
  @moduledoc """
  Parent reactor that recurses the revision reactor until the draft is approved.

  Uses `recurse` with `exit_condition` (approved == true) and `max_iterations 5`
  as a safety cap.
  """
  use Reactor, extensions: [AshDurableReactor]

  input :draft

  recurse :revision_loop, RecurseRevisionLoop.RevisionReactor do
    argument :draft, input(:draft)
    max_iterations 5
    exit_condition fn result -> result[:draft][:approved] == true end
  end

  return :revision_loop
end
