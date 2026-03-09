defmodule AccountabilityWorkflow.SampleData do
  @moduledoc false

  def weekly_checkin("communication-improvement") do
    %{
      "week" => "2026-W10",
      "goal" => "Respond with clarity and fewer hedges",
      "patterns" => ["long preambles", "soft commitments"],
      "checkins" => %{
        "2026-03-09" => %{"done" => false}
      }
    }
  end

  def weekly_checkin(_project) do
    %{
      "week" => "2026-W10",
      "goal" => "Ship one concrete improvement",
      "patterns" => [],
      "checkins" => %{}
    }
  end
end
