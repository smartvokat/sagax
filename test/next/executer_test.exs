defmodule Sagax.Next.ExecuterTest do
  alias Sagax.Next, as: Sagax
  alias Sagax.Executer
  alias Sagax.Test.Log

  import Sagax.Test.Assertions
  import Sagax.Test.Effects

  use ExUnit.Case

  setup do
    {:ok, log} = Log.start_link([])
    %{log: log}
  end

  describe "effects" do
    test "pass the current value to effects" do
      Sagax.new()
      |> Sagax.put("a", assert_value_effect(nil, {:ok, "a"}))
      |> Sagax.put("b", assert_value_effect(%{"a" => "a"}, {:ok, "b"}))
      |> Sagax.run(assert_value_effect(%{"a" => "a", "b" => "b"}))
      |> Executer.execute()
    end

    test "pass empty args by default" do
      Sagax.new()
      |> Sagax.run(fn _, args -> assert args == nil end)
      |> Executer.execute()
    end

    test "pass an empty context by default" do
      Sagax.new()
      |> Sagax.run(fn _, _, ctx -> assert ctx == nil end)
      |> Executer.execute()
    end

    test "pass the args to effects" do
      Sagax.new(args: %{some: :args})
      |> Sagax.run(fn _, args -> assert args == %{some: :args} end)
      |> Sagax.run(fn _, args, _ -> assert args == %{some: :args} end)
      |> Executer.execute()
    end

    test "pass the context to effects" do
      Sagax.new(context: %{some: :context})
      |> Sagax.run(fn _, _, ctx -> assert ctx == %{some: :context} end)
      |> Executer.execute()
    end

    test "execute correctly" do
      saga = Sagax.put(Sagax.new(), :hello, fn -> {:ok, :world} end)

      assert %Sagax{value: value} = Executer.execute(saga)
      assert value == %{hello: :world}
    end

    test "execute serial effects", %{log: l} do
      saga =
        Sagax.new()
        |> Sagax.put("a", fn -> Log.add(l, "a", {:ok, "a"}) end)
        |> Sagax.put("b", fn -> Log.add(l, "b", {:ok, "b"}) end)
        |> Sagax.put("c", fn -> Log.add(l, "c", {:ok, "c"}) end)

      assert %Sagax{state: :ok, value: value} = Executer.execute(saga)
      assert value == %{"a" => "a", "b" => "b", "c" => "c"}
      assert_log l, ["a", "b", "c"]
    end

    test "execute nested sagas", %{log: l} do
      nested_saga_1 =
        Sagax.new()
        |> Sagax.put("c1", assert_value_effect(%{"b" => nil}, {:ok, "c1"}))
        |> Sagax.put("c2", assert_value_effect(%{"b" => %{"c1" => "c1"}}, {:ok, "c2"}))

      nested_saga_2 =
        Sagax.new()
        |> Sagax.put("d", assert_value_effect(%{"f" => nil}, {:ok, "d"}))

      saga =
        Sagax.new()
        |> Sagax.put("a", fn -> Log.add(l, "a", {:ok, "a"}) end)
        |> Sagax.put("b", fn -> Log.add(l, "b", nested_saga_1) end)
        |> Sagax.put("f", nested_saga_2)

      assert %Sagax{state: :ok, value: value} = Executer.execute(saga)
      assert_log l, ["a", "b"]
      assert value == %{"a" => "a", "b" => %{"c1" => "c1", "c2" => "c2"}, "f" => %{"d" => "d"}}
    end
  end

  describe "compensate()" do
    test "compensates a simple saga with :noop compensations" do
      saga =
        Sagax.new()
        |> Sagax.put("a", assert_value_effect(nil, {:ok, "a"}))
        |> Sagax.put("b", assert_value_effect(%{"a" => "a"}, {:ok, "b"}))
        |> Sagax.put("c", fn -> {:error, "Something went wrong"} end)

      assert %Sagax{state: :error, value: value} = Executer.execute(saga)
      assert value == %{"a" => "a", "b" => "b", "c" => "Something went wrong"}
    end

    test "compensates a simple saga", %{log: log} do
      saga =
        Sagax.new()
        |> Sagax.put("a", fn -> {:error, "a"} end, fn -> Log.add(log, "a.comp", {:ok, "a"}) end)

      assert %Sagax{state: :error, value: value} = Executer.execute(saga)
      assert value == %{"a" => "a"}
      assert_log log, ["a.comp"]
    end

    test "compensates a simple saga with run step", %{log: log} do
      saga =
        Sagax.new()
        |> Sagax.run(fn -> {:error, "blah"} end, fn -> Log.add(log, "a.comp", {:ok, "a"}) end)

      assert %Sagax{state: :error, value: value} = Executer.execute(saga)
      assert value == %{}
      assert_log log, ["a.comp"]
    end

    test "compensates a nested saga", %{log: log} do
      nested_saga =
        Sagax.new()
        |> Sagax.put("b", fn -> {:ok, "b"} end, fn -> Log.add(log, "b.comp") end)
        |> Sagax.put("c", fn -> {:ok, "c"} end, fn -> Log.add(log, "c.comp") end)

      saga =
        Sagax.new()
        |> Sagax.put("a", fn -> {:ok, "a"} end)
        |> Sagax.run(nested_saga)
        |> Sagax.put("d", fn -> {:error, "d"} end, fn -> Log.add(log, "d.comp") end)


      assert %Sagax{state: :error, value: value} = Executer.execute(saga)
      assert value == %{"a" => "a", "d" => "d", "b" => "b", "c" => "c"}
      assert_log log, ["d.comp", "c.comp", "b.comp"]
    end
  end
end