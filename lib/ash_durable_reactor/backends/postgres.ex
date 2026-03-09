defmodule AshDurableReactor.Backends.Postgres do
  @moduledoc false

  defmacro define_backend(opts) do
    quote do
      AshDurableReactor.Backends.Postgres.__define_backend__(__ENV__, unquote(Macro.escape(opts)))
    end
  end

  def store_config(opts) do
    modules = modules(opts)

    [
      domain: modules.domain,
      run_resource: modules.run,
      step_resource: modules.step,
      event_resource: modules.event
    ]
  end

  def __define_backend__(env, opts) do
    modules = modules(opts)
    repo = Keyword.fetch!(opts, :repo)
    otp_app = Keyword.fetch!(opts, :otp_app)

    unless Code.ensure_loaded?(AshPostgres.DataLayer) do
      raise "ash_postgres is required to use `durable do; postgres ... end`"
    end

    unless Code.ensure_loaded?(modules.domain) do
      file = env.file || "nofile"

      Code.compile_string(domain_source(modules, otp_app), file)
      Code.compile_string(run_source(modules, repo), file)
      Code.compile_string(step_source(modules, repo), file)
      Code.compile_string(event_source(modules, repo), file)
    end

    :ok
  end

  def define_backend_quoted(opts) do
    quote do
      AshDurableReactor.Backends.Postgres.__define_backend__(
        __ENV__,
        unquote(Macro.escape(opts))
      )
    end
  end

  defp modules(opts) do
    root = Module.concat([Keyword.fetch!(opts, :repo), AshDurableReactor, Postgres])

    %{
      root: root,
      domain: Module.concat(root, Domain),
      run: Module.concat(root, Run),
      step: Module.concat(root, Step),
      event: Module.concat(root, Event)
    }
  end

  defp domain_source(modules, otp_app) do
    """
    defmodule #{inspect(modules.domain)} do
      use Ash.Domain,
        otp_app: #{inspect(otp_app)},
        validate_config_inclusion?: false

      resources do
        resource #{inspect(modules.run)}
        resource #{inspect(modules.step)}
        resource #{inspect(modules.event)}
      end
    end
    """
  end

  defp run_source(modules, repo) do
    """
    defmodule #{inspect(modules.run)} do
      use Ash.Resource,
        domain: #{inspect(modules.domain)},
        extensions: [AshPostgres.DataLayer],
        data_layer: AshPostgres.DataLayer

      import AshDurableReactor.Backends.Resource

      postgres do
        table "durable_runs"
        repo #{inspect(repo)}
      end

      run_fields()
    end
    """
  end

  defp step_source(modules, repo) do
    """
    defmodule #{inspect(modules.step)} do
      use Ash.Resource,
        domain: #{inspect(modules.domain)},
        extensions: [AshPostgres.DataLayer],
        data_layer: AshPostgres.DataLayer

      import AshDurableReactor.Backends.Resource

      postgres do
        table "durable_steps"
        repo #{inspect(repo)}
      end

      step_fields()
    end
    """
  end

  defp event_source(modules, repo) do
    """
    defmodule #{inspect(modules.event)} do
      use Ash.Resource,
        domain: #{inspect(modules.domain)},
        extensions: [AshPostgres.DataLayer],
        data_layer: AshPostgres.DataLayer

      import AshDurableReactor.Backends.Resource

      postgres do
        table "durable_events"
        repo #{inspect(repo)}
      end

      event_fields()
    end
    """
  end
end
