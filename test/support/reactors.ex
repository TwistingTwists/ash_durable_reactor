defmodule AshDurableReactor.TestReactors.ApprovalFlow do
  use Reactor, extensions: [AshDurableReactor]

  input(:value)

  step :seed do
    argument(:value, input(:value))

    run(fn %{value: value}, _context ->
      AshDurableReactor.TestCounter.bump(:seed)
      {:ok, value * 2}
    end)
  end

  step(:approval, AshDurableReactor.TestSteps.Approval)

  step :finalize do
    argument(:seed, result(:seed))
    argument(:approval, result(:approval))

    run(fn %{seed: seed, approval: approval}, _context ->
      AshDurableReactor.TestCounter.bump(:finalize)
      {:ok, "#{approval}:#{seed}"}
    end)
  end

  return(:finalize)
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

  input(:prefix)

  step :approval, AshDurableReactor.TestSteps.CustomResumable do
    argument(:prefix, input(:prefix))
  end

  return(:approval)
end

defmodule AshDurableReactor.TestReactors.UndoFlow do
  use Reactor, extensions: [AshDurableReactor]

  step :allocate do
    run(fn _, _context ->
      AshDurableReactor.TestCounter.bump(:allocate)
      {:ok, :allocated}
    end)

    undo(fn _value, _arguments, _context ->
      AshDurableReactor.TestCounter.bump(:undo_allocate)
      :ok
    end)
  end

  step :explode do
    run(fn _, _context ->
      {:error, :boom}
    end)
  end

  return(:explode)
end

defmodule AshDurableReactor.TestReactors.CompensationFlow do
  use Reactor, extensions: [AshDurableReactor]

  step :fragile do
    run(fn _, _context ->
      AshDurableReactor.TestCounter.bump(:fragile_run)
      {:error, :flaky}
    end)

    compensate(fn _reason, _arguments, _context ->
      AshDurableReactor.TestCounter.bump(:fragile_compensate)
      {:continue, :recovered}
    end)
  end

  return(:fragile)
end

defmodule AshDurableReactor.TestSteps.CountedDouble do
  use Reactor.Step

  @impl true
  def run(%{value: value}, _context, _options) do
    AshDurableReactor.TestCounter.bump(:counted_double)
    {:ok, value * 2}
  end
end

defmodule AshDurableReactor.TestSteps.CountedAddOne do
  use Reactor.Step

  @impl true
  def run(%{value: value}, _context, _options) do
    AshDurableReactor.TestCounter.bump(:counted_add_one)
    {:ok, value + 1}
  end
end

defmodule AshDurableReactor.TestReactors.SubReactor do
  use Reactor, extensions: [AshDurableReactor]

  input :value

  step :doubled, AshDurableReactor.TestSteps.CountedDouble do
    argument :value, input(:value)
  end

  step :plus_one, AshDurableReactor.TestSteps.CountedAddOne do
    argument :value, result(:doubled)
  end

  return :plus_one
end

defmodule AshDurableReactor.TestReactors.ComposeFlow do
  use Reactor, extensions: [AshDurableReactor]

  input :start_value

  compose :sub_calculation, AshDurableReactor.TestReactors.SubReactor do
    argument :value, input(:start_value)
  end

  step :finalize do
    argument :value, result(:sub_calculation)

    run fn %{value: v}, _ctx ->
      AshDurableReactor.TestCounter.bump(:finalize)
      {:ok, %{result: v, source: :composed}}
    end
  end

  return :finalize
end

defmodule AshDurableReactor.TestReactors.SwitchFlow do
  use Reactor, extensions: [AshDurableReactor]

  input :action
  input :value

  switch :route do
    on input(:action)

    matches? fn action -> action == :double end do
      step :do_double, AshDurableReactor.TestSteps.CountedDouble do
        argument :value, input(:value)
      end

      return :do_double
    end

    matches? fn action -> action == :add_one end do
      step :do_add, AshDurableReactor.TestSteps.CountedAddOne do
        argument :value, input(:value)
      end

      return :do_add
    end

    default do
      step :passthrough do
        argument :value, input(:value)
        run fn %{value: v}, _ctx -> {:ok, v} end
      end

      return :passthrough
    end
  end

  return :route
end

defmodule AshDurableReactor.TestSteps.RevisionStep do
  use Reactor.Step

  @impl true
  def run(%{draft: draft}, _context, _options) do
    revision = Map.get(draft, :revision_number, 0) + 1
    content = Map.get(draft, :content, "") <> " [rev#{revision}]"
    approved = revision >= 3

    AshDurableReactor.TestCounter.bump(:revision)

    {:ok, %{content: content, revision_number: revision, approved: approved}}
  end
end

defmodule AshDurableReactor.TestReactors.RevisionSubReactor do
  use Reactor, extensions: [AshDurableReactor]

  input :draft

  step :revise, AshDurableReactor.TestSteps.RevisionStep do
    argument :draft, input(:draft)
  end

  step :wrap_for_recurse do
    argument :result, result(:revise)
    run fn %{result: result}, _ctx -> {:ok, %{draft: result}} end
  end

  return :wrap_for_recurse
end

defmodule AshDurableReactor.TestReactors.RecurseFlow do
  use Reactor, extensions: [AshDurableReactor]

  input :draft

  recurse :revision_loop, AshDurableReactor.TestReactors.RevisionSubReactor do
    argument :draft, input(:draft)
    max_iterations 5
    exit_condition fn result -> result[:draft][:approved] == true end
  end

  return :revision_loop
end
