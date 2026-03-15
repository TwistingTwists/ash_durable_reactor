defmodule AshDurableReactorIntegrationTest do
  use ExUnit.Case, async: false

  alias AshDurableReactor.Store
  alias AshDurableReactor.TestCounter

  alias AshDurableReactor.TestReactors.{
    ApprovalFlow,
    CompensationFlow,
    ComposeFlow,
    CustomResumableFlow,
    RecurseFlow,
    SwitchFlow,
    UndoFlow
  }

  setup_all do
    start_supervised!(TestCounter)
    :ok
  end

  setup do
    Store.reset!()
    TestCounter.reset!()
    :ok
  end

  test "replays completed steps after a halted step is resumed" do
    run_id = "approval-1"

    assert {:halted, _reactor} =
             AshDurableReactor.run(
               ApprovalFlow,
               %{value: 3},
               %{request_id: "req-1"},
               run_id: run_id,
               async?: false
             )

    assert TestCounter.get(:seed) == 1
    assert TestCounter.get(:finalize) == 0

    assert %{status: :halted} = Store.get_run(run_id)
    assert %{status: :succeeded, output: 6} = Store.get_step(run_id, :seed)

    assert %{status: :halted, halt_payload: %{awaiting: :approval}} =
             Store.get_step(run_id, :approval)

    assert :ok = AshDurableReactor.resume_step(run_id, :approval, "approved")

    assert {:ok, "approved:6"} =
             AshDurableReactor.run(
               ApprovalFlow,
               %{value: 3},
               %{request_id: "req-1"},
               run_id: run_id,
               async?: false
             )

    assert TestCounter.get(:seed) == 1
    assert TestCounter.get(:finalize) == 1
    assert %{status: :succeeded, result: "approved:6"} = Store.get_run(run_id)
  end

  test "persists undo state when a downstream step fails" do
    run_id = "undo-1"

    assert {:error, error} =
             AshDurableReactor.run(
               UndoFlow,
               %{},
               %{request_id: "req-undo"},
               run_id: run_id,
               async?: false
             )

    assert inspect(error) =~ "boom"
    assert TestCounter.get(:allocate) == 1
    assert TestCounter.get(:undo_allocate) == 1
    assert %{status: :undone} = Store.get_step(run_id, :allocate)
    assert %{status: :failed} = Store.get_run(run_id)
  end

  test "custom step modules can implement resume/4" do
    run_id = "custom-resume-1"

    assert {:halted, _reactor} =
             AshDurableReactor.run(
               CustomResumableFlow,
               %{prefix: "done"},
               %{},
               run_id: run_id,
               async?: false
             )

    assert %{status: :halted, mode: :resumable} = Store.get_step(run_id, :approval)
    assert :ok = AshDurableReactor.resume_step(run_id, :approval, "approved")

    assert {:ok, "done:approved"} =
             AshDurableReactor.run(
               CustomResumableFlow,
               %{prefix: "done"},
               %{},
               run_id: run_id,
               async?: false
             )
  end

  test "persists compensation outcomes when a step recovers" do
    run_id = "compensate-1"

    assert {:ok, :recovered} =
             AshDurableReactor.run(
               CompensationFlow,
               %{},
               %{request_id: "req-compensate"},
               run_id: run_id,
               async?: false
             )

    assert TestCounter.get(:fragile_run) == 1
    assert TestCounter.get(:fragile_compensate) == 1
    assert %{status: :succeeded, output: :recovered} = Store.get_step(run_id, :fragile)
    assert %{status: :succeeded, result: :recovered} = Store.get_run(run_id)
  end

  test "compose returns sub-reactor result, not :pending_result" do
    run_id = "compose-1"

    assert {:ok, %{result: 11, source: :composed}} =
             AshDurableReactor.run(
               ComposeFlow,
               %{start_value: 5},
               %{},
               run_id: run_id,
               async?: false
             )

    assert TestCounter.get(:counted_double) == 1
    assert TestCounter.get(:counted_add_one) == 1
    assert TestCounter.get(:finalize) == 1
    assert %{status: :succeeded} = Store.get_run(run_id)
  end

  test "compose replays wrapped steps on second run, re-runs unwrapped compose" do
    run_id = "compose-replay-1"

    assert {:ok, %{result: 11, source: :composed}} =
             AshDurableReactor.run(ComposeFlow, %{start_value: 5}, %{}, run_id: run_id, async?: false)

    TestCounter.reset!()

    assert {:ok, %{result: 11, source: :composed}} =
             AshDurableReactor.run(ComposeFlow, %{start_value: 5}, %{}, run_id: run_id, async?: false)

    # compose meta-step is not wrapped, so it re-runs and its child reactor
    # re-executes (child steps are not individually durable)
    assert TestCounter.get(:counted_double) == 1
    assert TestCounter.get(:counted_add_one) == 1
    # finalize IS wrapped by StepWrapper, so it replays from store
    assert TestCounter.get(:finalize) == 0
  end

  test "switch routes to correct branch and returns actual value" do
    run_id = "switch-1"

    assert {:ok, 14} =
             AshDurableReactor.run(
               SwitchFlow,
               %{action: :double, value: 7},
               %{},
               run_id: run_id,
               async?: false
             )

    assert TestCounter.get(:counted_double) == 1
    assert %{status: :succeeded} = Store.get_run(run_id)
  end

  test "switch replays wrapped steps on second run, re-runs unwrapped branch" do
    run_id = "switch-replay-1"

    assert {:ok, 14} =
             AshDurableReactor.run(SwitchFlow, %{action: :double, value: 7}, %{}, run_id: run_id, async?: false)

    TestCounter.reset!()

    assert {:ok, 14} =
             AshDurableReactor.run(SwitchFlow, %{action: :double, value: 7}, %{}, run_id: run_id, async?: false)

    # switch meta-step is not wrapped, so it re-runs and emits fresh
    # branch steps (also unwrapped since they are dynamic)
    assert TestCounter.get(:counted_double) == 1
  end

  test "recurse loops all iterations and returns final result" do
    run_id = "recurse-1"
    initial_draft = %{content: "draft", revision_number: 0, approved: false}

    assert {:ok, result} =
             AshDurableReactor.run(
               RecurseFlow,
               %{draft: initial_draft},
               %{},
               run_id: run_id,
               async?: false
             )

    assert result.draft.approved == true
    assert result.draft.revision_number == 3
    assert TestCounter.get(:revision) == 3
    assert %{status: :succeeded} = Store.get_run(run_id)
  end

  test "recurse replays completed result on second run" do
    run_id = "recurse-replay-1"
    initial_draft = %{content: "draft", revision_number: 0, approved: false}

    assert {:ok, result} =
             AshDurableReactor.run(
               RecurseFlow,
               %{draft: initial_draft},
               %{},
               run_id: run_id,
               async?: false
             )

    assert result.draft.revision_number == 3
    assert TestCounter.get(:revision) == 3

    TestCounter.reset!()

    assert {:ok, replayed} =
             AshDurableReactor.run(
               RecurseFlow,
               %{draft: initial_draft},
               %{},
               run_id: run_id,
               async?: false
             )

    assert replayed == result
    assert TestCounter.get(:revision) == 0
  end
end
