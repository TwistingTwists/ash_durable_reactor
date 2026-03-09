defmodule AccountabilityWorkflow.Reactor do
  use Reactor, extensions: [AshDurableReactor]

  durable do
    persist_context [:agent_name, :trigger_type]
  end

  input :config
  input :phase

  step :extract_inputs do
    argument :config, input(:config)

    run fn %{config: config}, _ctx ->
      learnings = config["learnings_path"] || "~/Downloads/experiments/learnings"
      project = config["project"] || "communication-improvement"
      weeks_dir = Path.expand(Path.join([learnings, "projects", project, "weeks"]))
      trigger_type = config["trigger_type_override"] || "morning_prime"

      {:ok,
       %{
         weeks_dir: weeks_dir,
         project: project,
         trigger_type: trigger_type,
         week_override: config["week"]
       }}
    end
  end

  step :resolve_week_prefix do
    argument :inputs, result(:extract_inputs)

    run fn %{inputs: inputs}, _ctx ->
      prefix =
        case inputs.week_override do
          nil -> "2026-W10"
          override -> override
        end

      {:ok, %{weeks_dir: inputs.weeks_dir, prefix: prefix, project: inputs.project}}
    end
  end

  step :resolve_toml_path do
    argument :week, result(:resolve_week_prefix)
    run fn %{week: %{weeks_dir: dir, prefix: prefix}}, _ctx -> {:ok, Path.join(dir, "#{prefix}-checkin.toml")} end
  end

  step :resolve_md_path do
    argument :week, result(:resolve_week_prefix)
    run fn %{week: %{weeks_dir: dir, prefix: prefix}}, _ctx -> {:ok, Path.join(dir, "#{prefix}.md")} end
  end

  step :read_weekly_checkin do
    argument :week, result(:resolve_week_prefix)

    run fn %{week: %{project: project}}, _ctx ->
      {:ok, AccountabilityWorkflow.SampleData.weekly_checkin(project)}
    end
  end

  step :check_today do
    argument :toml_data, result(:read_weekly_checkin)

    run fn %{toml_data: data}, _ctx ->
      today = "2026-03-09"
      checked_in = get_in(data, ["checkins", today, "done"]) == true
      entry = get_in(data, ["checkins", today])
      {:ok, %{checked_in: checked_in, entry: entry, date: today}}
    end
  end

  step :build_message do
    argument :inputs, result(:extract_inputs)
    argument :toml_data, result(:read_weekly_checkin)
    argument :today_status, result(:check_today)
    argument :md_path, result(:resolve_md_path)

    run fn %{inputs: %{trigger_type: type}, toml_data: data, today_status: status, md_path: md_path}, _ctx ->
      message =
        case type do
          "morning_prime" ->
            "Morning prime for #{data["week"]}: focus on #{data["goal"]}. Review #{md_path}."

          "afternoon_check" ->
            if status.checked_in do
              "You already checked in today. Send a brief follow-up only if something changed."
            else
              "You have not checked in today. Review #{md_path} and reply with a short update."
            end
        end

      {:ok,
       %{
         message: message,
         context_type: "accountability_check",
         context_data: %{
           "phase" => type,
           "goal" => data["goal"],
           "patterns" => data["patterns"],
           "file_path" => md_path
         }
       }}
    end
  end

  step :send_message do
    argument :message_context, result(:build_message)

    run fn %{message_context: %{message: msg, context_type: type, context_data: data}}, _ctx ->
      {:ok,
       %{
         status: :sent,
         provider: :demo,
         message_id: "msg-1001",
         delivered_message: msg,
         context_type: type,
         context_data: data
       }}
    end
  end

  await_resume :checkin_reply

  step :record_checkin do
    argument :config, input(:config)
    argument :phase, input(:phase)
    argument :week_data, result(:read_weekly_checkin)
    argument :today_status, result(:check_today)
    argument :message_context, result(:build_message)
    argument :delivery, result(:send_message)
    argument :reply, result(:checkin_reply)
    argument :toml_path, result(:resolve_toml_path)

    run fn arguments, context ->
      {:ok,
       %{
         project: arguments.config["project"],
         phase: arguments.phase,
         date: arguments.today_status.date,
         toml_path: arguments.toml_path,
         original_goal: arguments.week_data["goal"],
         sent_message_id: arguments.delivery.message_id,
         prompt: arguments.message_context.message,
         reply: arguments.reply,
         trigger_type: context[:trigger_type],
         agent_name: context[:agent_name]
       }}
    end
  end

  return :record_checkin
end
