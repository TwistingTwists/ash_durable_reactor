defmodule ComposeWorkflow.Steps.EnrichData do
  use Reactor.Step

  @impl true
  def run(%{data: data}, _context, _options) do
    enriched = Map.put(data, :enriched, true)
    IO.puts("  [EnrichData] enriched data: #{inspect(enriched)}")
    {:ok, enriched}
  end
end

defmodule ComposeWorkflow.Steps.Validate do
  use Reactor.Step

  @impl true
  def run(%{data: data}, _context, _options) do
    validated = Map.put(data, :valid, true)
    IO.puts("  [Validate] validated data: #{inspect(validated)}")
    {:ok, validated}
  end
end

defmodule ComposeWorkflow.EnrichmentReactor do
  use Reactor, extensions: [AshDurableReactor]

  input :data

  step :enrich, ComposeWorkflow.Steps.EnrichData do
    argument :data, input(:data)
  end

  step :validate, ComposeWorkflow.Steps.Validate do
    argument :data, result(:enrich)
  end

  return :validate
end

defmodule ComposeWorkflow.PipelineReactor do
  use Reactor, extensions: [AshDurableReactor]

  input :raw_data

  step :prepare do
    argument :raw_data, input(:raw_data)

    run fn %{raw_data: raw_data}, _context ->
      prepared = Map.put(raw_data, :prepared, true)
      IO.puts("  [Prepare] prepared data: #{inspect(prepared)}")
      {:ok, prepared}
    end
  end

  compose :enrichment, ComposeWorkflow.EnrichmentReactor do
    argument :data, result(:prepare)
  end

  step :publish do
    argument :enriched, result(:enrichment)

    run fn %{enriched: enriched}, _context ->
      published = Map.put(enriched, :published, true)
      IO.puts("  [Publish] published data: #{inspect(published)}")
      {:ok, published}
    end
  end

  return :publish
end
