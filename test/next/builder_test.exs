defmodule Sagax.Next.BuilderTest do
  alias Sagax.Next, as: Sagax
  alias Sagax.Test.MockBuilder

  use ExUnit.Case

  test "executes a saga using Builder" do
    {:ok, %Sagax{value: value}} = MockBuilder.execute(%{}, %{}, [])

    assert value == %{"a" => "a", "b" => "b"}
  end
end
