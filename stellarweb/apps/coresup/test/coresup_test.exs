defmodule CoresupTest do
  use ExUnit.Case
  doctest Coresup

  test "greets the world" do
    assert Coresup.hello() == :world
  end
end
