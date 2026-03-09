defmodule AshDurableReactorTest do
  use ExUnit.Case
  doctest AshDurableReactor

  test "greets the world" do
    assert AshDurableReactor.hello() == :world
  end
end
