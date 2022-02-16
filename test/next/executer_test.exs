defmodule Sagax.Next.ExecuterTest do
  alias Sagax.Next, as: Sagax
  alias Sagax.{Error, Executer}
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

    test "stores 3rd tuple element into context" do
      saga =
        Sagax.new()
        |> Sagax.put(:hello, fn -> {:ok, "hello", %{some: "meta"}} end)
        |> Sagax.put(:world, fn -> {:halt, "world", %{other: "meta"}} end)
        |> Sagax.put("c", fn -> {:ok, "c", %{another: "meta"}} end)

      assert %Sagax{value: value, context: context, state: :halt} = Executer.execute(saga)
      assert %{some: "meta", other: "meta"} = context
      assert value == %{hello: "hello", world: "world"}
    end

    test "halts saga when run step halts" do
      saga =
        Sagax.new()
        |> Sagax.put(:hello, fn -> {:ok, "hello", %{some: "meta"}} end)
        |> Sagax.run(fn -> {:halt, "world", %{other: "meta"}} end)
        |> Sagax.put("c", fn -> {:ok, "c", %{another: "meta"}} end)

      assert %Sagax{value: value, context: context, state: :halt} = Executer.execute(saga)
      assert %{some: "meta", other: "meta"} = context
      assert value == %{hello: "hello"}
    end

    test "halts saga when run step halts without context" do
      saga =
        Sagax.new()
        |> Sagax.put(:hello, fn -> {:ok, "hello", %{some: "meta"}} end)
        |> Sagax.run(fn -> {:halt, "world"} end)
        |> Sagax.put("c", fn -> {:ok, "c", %{another: "meta"}} end)

      assert %Sagax{value: value, context: context, state: :halt} = Executer.execute(saga)
      assert %{some: "meta"} = context
      assert value == %{hello: "hello"}
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
        |> Sagax.put("c1", assert_value_effect(nil, {:ok, "c1"}))
        |> Sagax.put("c2", assert_value_effect(%{"c1" => "c1"}, {:ok, "c2"}))

      nested_saga_2 =
        Sagax.new()
        |> Sagax.put("d", assert_value_effect(nil, {:ok, "d"}))

      saga =
        Sagax.new()
        |> Sagax.put("a", fn -> Log.add(l, "a", {:ok, "a"}) end)
        |> Sagax.put("b", fn -> Log.add(l, "b", nested_saga_1) end)
        |> Sagax.put("f", nested_saga_2)

      assert %Sagax{state: :ok, value: value} = Executer.execute(saga)
      assert_log l, ["a", "b"]
      assert value == %{"a" => "a", "b" => %{"c1" => "c1", "c2" => "c2"}, "f" => %{"d" => "d"}}
    end

    test "execute deeply execute nested sagas" do
      nested_saga_4 =
        Sagax.new()
        |> Sagax.put("f", assert_value_effect(nil, {:ok, "f"}))
        |> Sagax.put("g", assert_value_effect(%{"f" => "f"}, {:ok, "g"}))

      nested_saga_3 =
        Sagax.new()
        |> Sagax.put("e", nested_saga_4)

      nested_saga_2 =
        Sagax.new()
        |> Sagax.put("d", nested_saga_3)

      nested_saga_1 =
        Sagax.new()
        |> Sagax.put("c", nested_saga_2)
        |> Sagax.put(
          "c1",
          assert_value_effect(
            %{"c" => %{"d" => %{"e" => %{"f" => "f", "g" => "g"}}}},
            {:ok, "c1"}
          )
        )

      saga =
        Sagax.new()
        |> Sagax.put("a", assert_value_effect(nil, {:ok, "a"}))
        |> Sagax.put("b", nested_saga_1)

      assert %Sagax{state: :ok, value: value} = Executer.execute(saga)

      assert value == %{
               "a" => "a",
               "b" => %{"c" => %{"d" => %{"e" => %{"f" => "f", "g" => "g"}}}, "c1" => "c1"}
             }
    end

    test "halts execution when a step returns :halt", %{log: log} do
      saga =
        Sagax.new()
        |> Sagax.put("a", fn -> {:ok, "a"} end, fn -> Log.add(log, "a.comp") end)
        |> Sagax.put("b", fn -> {:halt, "HALT!"} end)
        |> Sagax.put("c", fn -> {:ok, "c"} end)

      assert %Sagax{state: :halt, value: value} = Executer.execute(saga)
      assert value == %{"a" => "a", "b" => "HALT!"}
      assert_log log, []
    end

    test "halts execution of the nested saga only when nested saga's step returns :halt", %{
      log: log
    } do
      nested_saga =
        Sagax.new()
        |> Sagax.put("c", fn -> {:ok, "c"} end, fn -> Log.add(log, "c.comp") end)
        |> Sagax.put("d", fn -> {:halt, "nested HALT!"} end, fn -> Log.add(log, "d.comp") end)
        |> Sagax.put("e", fn -> {:ok, "e"} end, fn -> Log.add(log, "e.comp") end)

      saga =
        Sagax.new()
        |> Sagax.put("a", fn -> {:ok, "a"} end, fn -> Log.add(log, "a") end)
        |> Sagax.put("b", nested_saga)
        |> Sagax.put("f", fn -> {:ok, "f"} end)

      assert %Sagax{state: :halt, value: value} = Executer.execute(saga)
      assert value == %{"a" => "a", "b" => %{"c" => "c", "d" => "nested HALT!"}, "f" => "f"}
      assert_log log, []
    end

    test "raises an error when step raises an exception" do
      assert_raise(RuntimeError, "exception", fn ->
        Sagax.new()
        |> Sagax.run(fn -> raise "exception" end)
        |> Sagax.execute()
      end)
    end
  end

  describe "compensate()" do
    test "compensates a simple saga with :noop compensations" do
      saga =
        Sagax.new()
        |> Sagax.put("a", assert_value_effect(nil, {:ok, "a"}))
        |> Sagax.put("b", assert_value_effect(%{"a" => "a"}, {:ok, "b"}))
        |> Sagax.put("c", fn -> {:error, "Something went wrong"} end)

      assert %Sagax{errors: [%Error{path: "c", error: "Something went wrong"}]} =
               Executer.execute(saga)
    end

    test "compensates a simple saga", %{log: log} do
      saga =
        Sagax.new()
        |> Sagax.put("a", fn -> {:error, "a"} end, fn -> Log.add(log, "a.comp", {:ok, "a"}) end)

      assert %Sagax{errors: [%Error{path: "a", error: "a"}]} = Executer.execute(saga)
      assert_log log, ["a.comp"]
    end

    test "compensates a simple saga with run step", %{log: log} do
      saga =
        Sagax.new()
        |> Sagax.run(fn -> {:error, "blah"} end, fn -> Log.add(log, "a.comp", {:ok, "a"}) end)

      assert %Sagax{errors: [%Error{error: "blah"}]} = Executer.execute(saga)
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
        |> Sagax.put("d", fn -> {:error, "d"} end, fn -> {:error, "comp failed"} end)

      assert %Sagax{
               errors: [%Error{path: "d", error: "comp failed"}, %Error{path: "d", error: "d"}]
             } = Executer.execute(saga)

      assert_log log, ["c.comp", "b.comp"]
    end
  end
end
