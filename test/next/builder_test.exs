defmodule Sagax.Next.BuilderTest do
  use ExUnit.Case

  test "executes a succesful saga" do
    defmodule OkSaga do
      alias Sagax.Next, as: Sagax

      use Sagax.Builder

      defp new(args, context, opts) do
        Sagax.new(args: args, context: context, opts: opts)
        |> Sagax.put("a", fn -> {:ok, "a"} end)
        |> Sagax.put("b", fn -> {:ok, "b"} end)
      end
    end

    {:ok, values, meta} = OkSaga.execute(%{}, %{}, [])

    assert values == %{"a" => "a", "b" => "b"}
    assert meta == %{}
  end

  test "executes a erroneous saga" do
    defmodule ErrorSaga do
      alias Sagax.Next, as: Sagax

      use Sagax.Builder

      defp new(args, context, opts) do
        Sagax.new(args: args, context: context, opts: opts)
        |> Sagax.put("a", fn -> {:ok, "a"} end)
        |> Sagax.put("b", fn -> {:error, "b"} end)
      end
    end

    {:error, errors, meta} = ErrorSaga.execute(%{}, %{}, [])

    assert [%Sagax.Next.Error{error: "b", path: "b"}] = errors
    assert meta == %{}
  end

  test "executes a halted saga" do
    defmodule HaltSaga do
      alias Sagax.Next, as: Sagax

      use Sagax.Builder

      defp new(args, context, opts) do
        Sagax.new(args: args, context: context, opts: opts)
        |> Sagax.put("a", fn -> {:ok, "a"} end)
        |> Sagax.put("b", fn -> {:halt, "b"} end)
        |> Sagax.put("c", fn -> {:ok, "c"} end)
      end
    end

    {:halt, values, meta} = HaltSaga.execute(%{}, %{}, [])

    assert values == %{"a" => "a", "b" => "b"}
    assert meta == %{}
  end

  test "returns context as 3rd tuple element" do
    defmodule MetaSaga do
      alias Sagax.Next, as: Sagax

      use Sagax.Builder

      defp new(args, context, opts) do
        Sagax.new(args: args, context: context, opts: opts)
        |> Sagax.put("a", fn -> {:ok, "a", %{some: "meta"}} end)
        |> Sagax.put("b", fn -> {:ok, "b", %{more: "meta"}} end)
      end
    end

    {:ok, values, meta} = MetaSaga.execute(%{}, %{ctx: %{my: "context"}}, [])

    assert values == %{"a" => "a", "b" => "b"}
    assert %{ctx: %{my: "context"}, some: "meta", more: "meta"} = meta
  end
end
