defmodule AccountabilityWorkflow.Demo do
  @moduledoc """
  Accountability workflow demo with configurable verbosity.

  Usage:
    AccountabilityWorkflow.Demo.run()           # concise mode (default)
    AccountabilityWorkflow.Demo.run(:concise)   # concise mode
    AccountabilityWorkflow.Demo.run(:verbose)   # verbose mode with full IO.inspect
  """

  alias AshDurableReactor.Store
  alias AccountabilityWorkflow.DemoHelper

  def run(mode \\ :concise)

  def run(:concise) do
    Store.reset!()

    run_id = "accountability-demo"

    config = %{
      "learnings_path" => "~/Downloads/experiments/learnings",
      "project" => "communication-improvement",
      "trigger_type_override" => "afternoon_check"
    }
    phase = "afternoon_check"

    DemoHelper.print_step("Initial Execution")
    DemoHelper.print_reactor_info(AccountabilityWorkflow.ReactorNative)
    DemoHelper.print_run_id(run_id)

    _first =
      AccountabilityWorkflow.ReactorNative.start(
        config,
        phase,
        run_id: run_id
      )

    IO.puts("")
    IO.puts(IO.ANSI.green() <> "✓ Execution halted" <> IO.ANSI.reset())

    DemoHelper.print_step_execution(run_id)

    DemoHelper.print_step("Resume & Replay")
    resume_payload = %{
      "done" => true,
      "reply_text" => "I reviewed the note and wrote today's update."
    }
    DemoHelper.print_resume_step(run_id, :checkin_reply, resume_payload)

    :ok = AshDurableReactor.resume_step(run_id, :checkin_reply, resume_payload)

    IO.puts("")

    _second =
      AccountabilityWorkflow.ReactorNative.start(
        config,
        phase,
        run_id: run_id
      )

    IO.puts(IO.ANSI.green() <> "✓ All steps completed successfully" <> IO.ANSI.reset())

    DemoHelper.print_step_execution(run_id)

    IO.puts("\n" <> IO.ANSI.green() <> "✓ Demo completed!" <> IO.ANSI.reset())
  end

  def run(:verbose) do
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
