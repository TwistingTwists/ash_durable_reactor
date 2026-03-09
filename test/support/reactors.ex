defmodule AshDurableReactor.TestReactors.ApprovalFlow do
  use Reactor, extensions: [AshDurableReactor]

  durable do
    persist_context [:request_id]
  end

  input :value

  step :seed do
    argument :value, input(:value)

    run fn %{value: value}, _context ->
      AshDurableReactor.TestCounter.bump(:seed)
      {:ok, value * 2}
    end
  end

  step :approval, AshDurableReactor.TestSteps.Approval

  step :finalize do
    argument :seed, result(:seed)
    argument :approval, result(:approval)

    run fn %{seed: seed, approval: approval}, _context ->
      AshDurableReactor.TestCounter.bump(:finalize)
      {:ok, "#{approval}:#{seed}"}
    end
  end

  return :finalize
end

defmodule AshDurableReactor.TestSteps.CustomResumable do
  use Reactor.Step

  @impl true
  def run(_arguments, _context, _options) do
    {:halt, %{awaiting: :custom_resume}}
  end

  def resume(arguments, _context, _options, persisted_step) do
    {:ok, "#{arguments.prefix}:#{persisted_step.resume_payload}"}
  end
end

defmodule AshDurableReactor.TestReactors.CustomResumableFlow do
  use Reactor, extensions: [AshDurableReactor]

  input :prefix

  step :approval, AshDurableReactor.TestSteps.CustomResumable do
    argument :prefix, input(:prefix)
  end

  return :approval
end

defmodule AshDurableReactor.TestReactors.UndoFlow do
  use Reactor, extensions: [AshDurableReactor]

  durable do
    persist_context [:request_id]
  end

  step :allocate do
    run fn _, _context ->
      AshDurableReactor.TestCounter.bump(:allocate)
      {:ok, :allocated}
    end

    undo fn _value, _arguments, _context ->
      AshDurableReactor.TestCounter.bump(:undo_allocate)
      :ok
    end
  end

  step :explode do
    run fn _, _context ->
      {:error, :boom}
    end
  end

  return :explode
end

defmodule AshDurableReactor.TestReactors.CompensationFlow do
  use Reactor, extensions: [AshDurableReactor]

  durable do
    persist_context [:request_id]
  end

  step :fragile do
    run fn _, _context ->
      AshDurableReactor.TestCounter.bump(:fragile_run)
      {:error, :flaky}
    end

    compensate fn _reason, _arguments, _context ->
      AshDurableReactor.TestCounter.bump(:fragile_compensate)
      {:continue, :recovered}
    end
  end

  return :fragile
end
