defmodule AccountabilityWorkflow.DemoHelper do
  @moduledoc """
  Helpers for detailed demo output with step execution tracking.
  """

  def print_section(title) do
    IO.puts("\n" <> IO.ANSI.cyan() <> ">>> #{title}" <> IO.ANSI.reset())
  end

  def print_step(title) do
    print_section(title)
  end

  def print_reactor_info(reactor_module) do
    IO.puts(IO.ANSI.light_black() <> "   Reactor: #{inspect(reactor_module)}" <> IO.ANSI.reset())
  end

  def print_run_id(run_id) do
    IO.puts(IO.ANSI.light_black() <> "   Run ID: #{run_id}" <> IO.ANSI.reset())
  end

  def print_step_execution(run_id) do
    steps = AshDurableReactor.list_steps(run_id)
    completed = Enum.filter(steps, fn s -> s.status != :halted end)
    halted = Enum.find(steps, fn s -> s.status == :halted end)

    IO.puts(IO.ANSI.green() <> "✓ Execution Summary" <> IO.ANSI.reset())
    IO.puts("  #{Enum.count(completed)}/#{Enum.count(steps)} steps completed")

    Enum.each(completed, fn step ->
      mode_tag = if step.mode == :resumable, do: " [resumable]", else: ""
      IO.puts("    ✓ #{step.step_name}#{mode_tag}")
    end)

    if halted do
      IO.puts("  #{IO.ANSI.yellow()}⊘ halted: #{halted.step_name}#{IO.ANSI.reset()}")
      if Map.get(halted, :halt_payload) && is_map(halted.halt_payload) do
        payload_summary = 
          halted.halt_payload
          |> Map.take([:awaiting, :prompt])
          |> Map.to_list()
          |> Enum.map(fn {k, v} -> "#{k}: #{inspect(v, limit: 1)}" end)
          |> Enum.join(", ")
        
        if payload_summary != "" do
          IO.puts("    └─ payload: #{payload_summary}")
        end
      end
    end
  end

  def print_resume_step(run_id, step_name, resume_payload) do
    payload_str = 
      resume_payload
      |> Enum.map(fn {k, v} -> "#{k}: #{inspect(v, limit: 1)}" end)
      |> Enum.join(", ")

    IO.puts(IO.ANSI.light_black() <> "   Resuming step: #{step_name}" <> IO.ANSI.reset())
    IO.puts(IO.ANSI.light_black() <> "   Run ID: #{run_id}" <> IO.ANSI.reset())
    IO.puts(IO.ANSI.light_black() <> "   Payload: {#{payload_str}}" <> IO.ANSI.reset())
    IO.puts(IO.ANSI.light_black() <> "   Mode: replay all steps from checkpoint" <> IO.ANSI.reset())
  end

  def print_run_summary(run_id) do
    case AshDurableReactor.get_run(run_id) do
      nil ->
        IO.puts(IO.ANSI.yellow() <> "⚠ No run found" <> IO.ANSI.reset())

      run ->
        IO.puts(IO.ANSI.green() <> "✓ Run Status" <> IO.ANSI.reset())
        IO.puts("  Status: #{run.status}")
        IO.puts("  Attempt: #{run.attempt}")
        IO.puts("  Updated: #{format_time(run.updated_at)}")

        if Map.get(run, :halt_reason) do
          IO.puts("  Halted at: #{run.halt_reason.step}")
        end

        if Map.get(run, :result) do
          IO.puts("  Result: #{inspect(Map.get(run, :result), pretty: true, limit: 3)}")
        end

        if Map.get(run, :error) do
          IO.puts("  Error: #{inspect(Map.get(run, :error))}")
        end
    end
  end

  def print_steps_summary(run_id) do
    steps = AshDurableReactor.list_steps(run_id)

    IO.puts(IO.ANSI.green() <> "✓ Step Summary (#{Enum.count(steps)} steps)" <> IO.ANSI.reset())

    steps
    |> Enum.group_by(& &1.status)
    |> Enum.each(fn {status, group_steps} ->
      color = status_color(status)
      IO.puts("  #{color}#{status}#{IO.ANSI.reset()}: #{Enum.count(group_steps)} steps")

      group_steps
      |> Enum.each(fn step ->
        mode = if step.mode == :resumable, do: " [resumable]", else: ""
        IO.puts("    • #{step.step_name}#{mode}")
      end)
    end)
  end

  defp status_color(:succeeded), do: IO.ANSI.green()
  defp status_color(:halted), do: IO.ANSI.yellow()
  defp status_color(:failed), do: IO.ANSI.red()
  defp status_color(_), do: IO.ANSI.reset()

  defp format_time(datetime) do
    datetime
    |> DateTime.to_naive()
    |> NaiveDateTime.to_string()
    |> String.slice(0..18)
  end
end
