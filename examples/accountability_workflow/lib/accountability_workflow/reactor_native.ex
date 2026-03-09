defmodule AccountabilityWorkflow.ReactorNative do
  @moduledoc """
  Reactor-native accountability workflow example.

  This example keeps the normal Reactor authoring model intact:

  - plain `input`
  - plain `step`
  - plain `argument` and `result`
  - one resumable step implemented as an ordinary step module

  `AshDurableReactor` provides durability as a wrapper around step execution.
  Replayable mode is inferred by default, and the reply step becomes resumable
  because its implementation exports `resume/4`.
  """

  use Reactor, extensions: [AshDurableReactor]

  durable do
    persist_context [:agent_name, :trigger_type]
  end

  input :config
  input :phase

  step :extract_inputs, __MODULE__.ExtractInputs do
    argument :config, input(:config)
  end

  step :resolve_week, __MODULE__.ResolveWeek do
    argument :inputs, result(:extract_inputs)
  end

  step :read_weekly_checkin, __MODULE__.ReadWeeklyCheckin do
    argument :inputs, result(:extract_inputs)
    argument :week, result(:resolve_week)
  end

  step :check_today, __MODULE__.CheckToday do
    argument :week_data, result(:read_weekly_checkin)
  end

  step :build_message, __MODULE__.BuildMessage do
    argument :phase, input(:phase)
    argument :inputs, result(:extract_inputs)
    argument :week_data, result(:read_weekly_checkin)
    argument :today_status, result(:check_today)
  end

  step :send_telegram_message, __MODULE__.SendTelegramMessage do
    argument :message_context, result(:build_message)
  end

  step :checkin_reply, __MODULE__.CheckinReply do
    argument :delivery, result(:send_telegram_message)
    argument :message_context, result(:build_message)
  end

  step :record_checkin, __MODULE__.RecordCheckin do
    argument :config, input(:config)
    argument :phase, input(:phase)
    argument :inputs, result(:extract_inputs)
    argument :week_data, result(:read_weekly_checkin)
    argument :today_status, result(:check_today)
    argument :message_context, result(:build_message)
    argument :delivery, result(:send_telegram_message)
    argument :reply, result(:checkin_reply)
  end

  return :record_checkin

  def start(config, phase, opts \\ []) do
    run_id = Keyword.fetch!(opts, :run_id)

    context = %{
      agent_name: "accountability_agent",
      trigger_type: config["trigger_type_override"] || phase
    }

    AshDurableReactor.run(__MODULE__, %{config: config, phase: phase}, context, run_id: run_id)
  end

  def resume(run_id, reply_payload) do
    AshDurableReactor.resume_step(run_id, :checkin_reply, reply_payload)
  end

  defmodule ExtractInputs do
    use Reactor.Step

    @impl true
    def run(%{config: config}, _context, _opts) do
      learnings_root = config["learnings_path"] || "~/Downloads/experiments/learnings"
      project = config["project"] || "communication-improvement"
      weeks_dir = Path.expand(Path.join([learnings_root, "projects", project, "weeks"]))

      {:ok,
       %{
         project: project,
         weeks_dir: weeks_dir,
         trigger_type: config["trigger_type_override"] || "morning_prime",
         week_override: config["week"]
       }}
    end
  end

  defmodule ResolveWeek do
    use Reactor.Step

    @impl true
    def run(%{inputs: inputs}, _context, _opts) do
      {:ok, inputs.week_override || "2026-W10"}
    end
  end

  defmodule ReadWeeklyCheckin do
    use Reactor.Step

    @impl true
    def run(%{inputs: inputs, week: week}, _context, _opts) do
      md_path = Path.join(inputs.weeks_dir, "#{week}.md")

      {:ok,
       %{
         "week" => week,
         "project" => inputs.project,
         "goal" => "Ship the durable Reactor API sketch",
         "patterns" => [
           "prefer normal Reactor steps",
           "keep durability at the step boundary"
         ],
         "file_path" => md_path,
         "checkins" => %{
           "2026-03-09" => %{
             "done" => false,
             "summary" => nil
           }
         }
       }}
    end
  end

  defmodule CheckToday do
    use Reactor.Step

    @impl true
    def run(%{week_data: week_data}, _context, _opts) do
      today = "2026-03-09"
      entry = get_in(week_data, ["checkins", today]) || %{}

      {:ok,
       %{
         date: today,
         checked_in: entry["done"] == true,
         entry: entry
       }}
    end
  end

  defmodule BuildMessage do
    use Reactor.Step

    @impl true
    def run(%{phase: phase, inputs: inputs, week_data: week_data, today_status: today_status}, _context, _opts) do
      message =
        case {phase, today_status.checked_in} do
          {"morning_prime", _} ->
            "Morning prime for #{week_data["week"]}: focus on #{week_data["goal"]}. Review #{week_data["file_path"]}."

          {"afternoon_check", true} ->
            "You already checked in today. Send a short follow-up only if something changed."

          {"afternoon_check", false} ->
            "You have not checked in today for #{inputs.project}. Review #{week_data["file_path"]} and reply with a short update."

          _ ->
            "Reply with your current accountability update for #{inputs.project}."
        end

      {:ok,
       %{
         message: message,
         context_type: "accountability_check",
         context_data: %{
           "phase" => phase,
           "goal" => week_data["goal"],
           "patterns" => week_data["patterns"],
           "file_path" => week_data["file_path"]
         }
       }}
    end
  end

  defmodule SendTelegramMessage do
    use Reactor.Step

    @impl true
    def run(%{message_context: %{message: message} = message_context}, _context, _opts) do
      IO.puts("[telegram] #{message}")

      {:ok,
       %{
         status: :sent,
         provider: :telegram,
         message_id: "tg-msg-1001",
         delivered_message: message,
         context_type: message_context.context_type,
         context_data: message_context.context_data
       }}
    end
  end

  defmodule CheckinReply do
    use Reactor.Step

    @impl true
    def run(%{delivery: delivery, message_context: message_context}, _context, _opts) do
      {:halt,
       %{
         awaiting: :telegram_reply,
         message_id: delivery.message_id,
         prompt: message_context.message
       }}
    end

    def resume(_arguments, _context, _opts, persisted_step) do
      {:ok, persisted_step.resume_payload}
    end
  end

  defmodule RecordCheckin do
    use Reactor.Step

    @impl true
    def run(arguments, context, _opts) do
      {:ok,
       %{
         project: arguments.inputs.project,
         phase: arguments.phase,
         date: arguments.today_status.date,
         original_goal: arguments.week_data["goal"],
         prompt: arguments.message_context.message,
         sent_message_id: arguments.delivery.message_id,
         reply: arguments.reply,
         trigger_type: context[:trigger_type],
         agent_name: context[:agent_name],
         status: :recorded
       }}
    end
  end
end
