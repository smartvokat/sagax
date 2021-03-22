defmodule Sagax.TaskExecuterTest do
  alias Sagax.Test.Log

  import Sagax.Test.Assertions

  alias Sagax
  alias Sagax.TaskExecuter, as: Executer

  use ExUnit.Case

  setup do
    {:ok, log} = Log.start_link([])
    %{log: log}
  end

  describe "effects" do
    test "execute correctly" do
      saga = Sagax.put(Sagax.new(), :hello, fn -> {:ok, :world} end)
      assert %Sagax{value: value} = Executer.execute(saga)
      assert value == %{hello: :world}
    end

    test "execute sequentially", %{log: l} do
      saga =
        Sagax.new()
        |> Sagax.put("a", fn -> Log.add(l, "a", {:ok, "a"}) end)
        |> Sagax.put("b", fn -> Log.add(l, "b", {:ok, "b"}) end)
        |> Sagax.put("c", fn -> Log.add(l, "c", {:ok, "c"}) end)

      assert %Sagax{value: value} = Executer.execute(saga)
      assert value == %{"a" => "a", "b" => "b", "c" => "c"}
      assert_log l, ["a", "b", "c"]
    end

    test "pass the previous value to next effects" do
      Sagax.new()
      |> Sagax.put("a", fn value ->
        assert value == nil
        {:ok, "a"}
      end)
      |> Sagax.put("b", fn value ->
        assert value == %{"a" => "a"}
        {:ok, "b"}
      end)
      |> Sagax.run(fn value ->
        assert value == %{"a" => "a", "b" => "b"}
      end)
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

    test "handle unexpected return values" do
      saga = Sagax.put(Sagax.new(), :a, fn -> :some_unexpected_value end)
      assert %Sagax{errors: [exception]} = Executer.execute(saga)
      assert exception.message =~ "Unexpected result of effect"
    end

    # test "handle dynamic nested sagas" do
    #   b =
    #     Sagax.new()
    #     |> Sagax.put(:b, fn value ->
    #       refute value
    #       {:ok, :b}
    #     end)
    #     |> Sagax.put(:c, fn value ->
    #       assert value == %{b: :b}
    #       {:ok, :c}
    #     end)

    #   a =
    #     Sagax.new()
    #     |> Sagax.put(:b, fn -> b end)
    #     |> Sagax.put(:d, fn value ->
    #       assert value == %{b: :b, c: :c}
    #       {:ok, %{d: :d}}
    #     end)

    #   saga = Sagax.put(Sagax.new(), :a, fn -> a end)
    #   assert %Sagax{value: value, errors: []} = Executer.execute(saga)
    #   assert value == %{a: %{b: %{b: :b, c: :c}, d: :d}}
    # end
  end

  # describe "compensations" do
  #   test "handle unexpected return values", %{log: l} do
  #     saga =
  #       Sagax.run(Sagax.new(), fn -> Log.add(l, "a", :error) end, fn _ ->
  #         Log.add(l, "_a", nil)
  #       end)

  #     assert %Sagax{errors: [exception]} = Executer.execute(saga)
  #     assert exception.message =~ "Unexpected result of compensation"
  #     assert_log l, ["a", "_a"]
  #   end
  # end

  # describe "with :run ops" do
  #   test "execute simple compensations sequentially", %{log: l} do
  #     saga =
  #       Sagax.new()
  #       |> Sagax.run(fn -> Log.add(l, "a") end, fn _ -> Log.add(l, "_a", :ok) end)
  #       |> Sagax.run(fn -> Log.add(l, "b") end, fn _ -> Log.add(l, "_b", :ok) end)
  #       |> Sagax.run(fn -> Log.add(l, "c", :error) end, fn _ -> Log.add(l, "_c", :ok) end)

  #     assert %Sagax{errors: []} = Executer.execute(saga)
  #     assert_log l, ["a", "b", "c", "_c", "_b", "_a"]
  #   end
  # end
end
