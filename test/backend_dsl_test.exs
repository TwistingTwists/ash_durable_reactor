defmodule AshDurableReactor.BackendDslTest do
  use ExUnit.Case, async: true

  test "rejects configuring both sqlite and postgres" do
    assert_raise Spark.Error.DslError, ~r/sqlite.*postgres|postgres.*sqlite/, fn ->
      Code.compile_string("""
      defmodule BackendDslConflict do
        use Reactor, extensions: [AshDurableReactor]

        durable do
          sqlite repo: Demo.SqliteRepo
          postgres repo: Demo.PostgresRepo
        end

        step :ok do
          run fn _, _ -> {:ok, :ok} end
        end

        return :ok
      end
      """)
    end
  end

  test "rejects mixing backend shortcuts with manual store config" do
    assert_raise Spark.Error.DslError, ~r/manual `store` or `store_config`/, fn ->
      Code.compile_string("""
      defmodule BackendDslMixedConfig do
        use Reactor, extensions: [AshDurableReactor]

        durable do
          sqlite repo: Demo.SqliteRepo
          store AshDurableReactor.AshStore
          store_config domain: Demo.Domain
        end

        step :ok do
          run fn _, _ -> {:ok, :ok} end
        end

        return :ok
      end
      """)
    end
  end
end
