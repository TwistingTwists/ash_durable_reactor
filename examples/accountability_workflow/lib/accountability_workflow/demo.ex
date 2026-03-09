defmodule AccountabilityWorkflow.Demo do
  @moduledoc false

  alias AshDurableReactor.Store

  def run do
    Store.reset!()

    run_id = "accountability-demo"

    config = %{
      "learnings_path" => "~/Downloads/experiments/learnings",
      "project" => "communication-improvement",
      "trigger_type_override" => "afternoon_check"
    }
    phase = "afternoon_check"

    first =
      AccountabilityWorkflow.ReactorNative.start(
        config,
        phase,
        run_id: run_id
      )

    IO.inspect(first, label: "first run")
    IO.inspect(AshDurableReactor.get_run(run_id), label: "persisted run after halt")
    IO.inspect(AshDurableReactor.list_steps(run_id), label: "persisted steps after halt")

    :ok =
      AshDurableReactor.resume_step(
        run_id,
        :checkin_reply,
        %{
          "done" => true,
          "reply_text" => "I reviewed the note and wrote today's update."
        }
      )

    second =
      AccountabilityWorkflow.ReactorNative.start(
        config,
        phase,
        run_id: run_id
      )

    IO.inspect(second, label: "second run")
    IO.inspect(AshDurableReactor.get_run(run_id), label: "persisted run after resume")
    IO.inspect(AshDurableReactor.list_steps(run_id), label: "persisted steps after resume")
  end
end
