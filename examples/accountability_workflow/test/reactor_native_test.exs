defmodule AccountabilityWorkflow.ReactorNativeTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias AshDurableReactor.Store
  alias AccountabilityWorkflow.ReactorNative

  setup do
    Store.reset!()
    :ok
  end

  test "halts on reply, resumes with the same run_id, and does not resend the telegram message" do
    run_id = "accountability-reactor-native-1"

    config = %{
      "learnings_path" => "~/Downloads/experiments/learnings",
      "project" => "communication-improvement",
      "trigger_type_override" => "afternoon_check"
    }

    first_output =
      capture_io(fn ->
        assert {:halted, _reactor} =
                 ReactorNative.start(config, "afternoon_check", run_id: run_id)
      end)

    assert first_output =~ "[telegram]"

    assert %{status: :halted} = Store.get_run(run_id)
    assert %{status: :succeeded} = Store.get_step(run_id, :extract_inputs)
    assert %{status: :succeeded} = Store.get_step(run_id, :build_message)
    assert %{status: :succeeded, output: %{provider: :telegram}} =
             Store.get_step(run_id, :send_telegram_message)

    assert %{status: :halted, mode: :resumable, halt_payload: %{awaiting: :telegram_reply}} =
             Store.get_step(run_id, :checkin_reply)

    assert :ok =
             ReactorNative.resume(run_id, %{
               "done" => true,
               "reply_text" => "I reviewed the API draft and recorded today's update."
             })

    second_output =
      capture_io(fn ->
        assert {:ok, result} =
                 ReactorNative.start(config, "afternoon_check", run_id: run_id)

        assert result.status == :recorded
        assert result.sent_message_id == "tg-msg-1001"
        assert result.reply["done"] == true
      end)

    assert second_output == ""
    assert %{status: :succeeded, result: %{status: :recorded}} = Store.get_run(run_id)
    assert %{status: :succeeded} = Store.get_step(run_id, :record_checkin)
  end
end
