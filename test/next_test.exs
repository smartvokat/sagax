defmodule Sagax.NextTest do
  alias Sagax.Next, as: Sagax
  alias Sagax.{Executer, Op, TestRepo}
  alias Sagax.Test.Log

  require Sagax.Op

  use ExUnit.Case

  import Sagax.Test.Assertions

  doctest Sagax

  describe "new()" do
    test "initializes without args" do
      assert saga = Sagax.new()
      assert saga.args == nil
    end
  end

  describe "put()" do
    test "adds the op correctly" do
      assert saga = Sagax.put(Sagax.new(), :hello, &IO.puts/1)
      assert length(saga.ops) == 1
      assert Op.op(Enum.at(saga.ops, 0), :type) == :put
      assert Op.op(Enum.at(saga.ops, 0), :opts) == [key: :hello]
    end
  end

  describe "put_if/4" do
    test "handles boolean conditions correctly" do
      assert %Sagax{value: %{hello: :world}} =
               Sagax.new()
               |> Sagax.put_if(true, :hello, fn -> {:ok, :world} end)
               |> Sagax.execute()

      assert %Sagax{value: %{}} =
               Sagax.new()
               |> Sagax.put_if(false, :hello, fn -> {:ok, :world} end)
               |> Sagax.execute()
    end

    test "handles functional conditions correctly" do
      assert %Sagax{value: %{hello: :world}} =
               Sagax.new()
               |> Sagax.put_if(fn -> true end, :hello, fn -> {:ok, :world} end)
               |> Sagax.execute()

      assert %Sagax{value: %{}} =
               Sagax.new()
               |> Sagax.put_if(fn -> false end, :hello, fn -> {:ok, :world} end)
               |> Sagax.execute()
    end

    test "raises when condition is not valid" do
      assert_raise ArgumentError, "Expected condition to return a boolean value", fn ->
        Sagax.new()
        |> Sagax.put_if(fn -> %{} end, :hello, fn -> {:ok, :world} end)
        |> Sagax.execute()
      end

      assert_raise ArgumentError, "Expected condition to be a boolean or function", fn ->
        Sagax.new()
        |> Sagax.put_if(%{}, :hello, fn -> {:ok, :world} end)
        |> Sagax.execute()
      end
    end
  end

  describe "run/3" do
    test "adds the op correctly" do
      effect = fn _, _ -> nil end
      comp = fn _, _, _ -> nil end

      assert saga = Sagax.run(Sagax.new(), effect, comp)
      assert length(saga.ops) == 1
      assert Op.op(Enum.at(saga.ops, 0), :type) == :run
      assert Op.op(Enum.at(saga.ops, 0), :effect) == effect
      assert Op.op(Enum.at(saga.ops, 0), :comp) == comp
    end
  end

  describe "run_if/4" do
    setup do
      {:ok, log} = Log.start_link([])
      %{log: log}
    end

    test "handles boolean conditions correctly", %{log: l} do
      Sagax.new()
      |> Sagax.run_if(true, fn -> Log.add(l, "a", :ok) end)
      |> Sagax.execute()

      Sagax.new()
      |> Sagax.run_if(false, fn -> Log.add(l, "b", :ok) end)
      |> Sagax.execute()

      assert_log l, ["a"]
    end

    test "handles functional conditions correctly", %{log: l} do
      Sagax.new()
      |> Sagax.run_if(fn -> true end, fn -> Log.add(l, "a", :ok) end)
      |> Sagax.execute()

      Sagax.new()
      |> Sagax.run_if(fn -> false end, fn -> Log.add(l, "b", :ok) end)
      |> Sagax.execute()

      assert_log l, ["a"]
    end

    test "raises when condition is not valid" do
      assert_raise ArgumentError, "Expected condition to return a boolean value", fn ->
        Sagax.new()
        |> Sagax.run_if(fn -> %{} end, fn -> {:ok, :world} end)
        |> Sagax.execute()
      end

      assert_raise ArgumentError, "Expected condition to be a boolean or function", fn ->
        Sagax.new()
        |> Sagax.run_if(%{}, fn -> {:ok, :world} end)
        |> Sagax.execute()
      end
    end
  end

  describe "transaction/2" do
    setup do
      {:ok, log} = Log.start_link([])
      %{log: log}
    end

    test "executes the saga in a transaction" do
      saga =
        Sagax.new()
        |> Sagax.run(fn -> {:ok, "value"} end)
        |> Sagax.transaction(TestRepo)

      %Sagax{state: :ok, value: %{}} = Executer.execute(saga)

      assert_receive {:transaction, _fun, []}
    end

    test "accepts transaction options" do
      saga =
        Sagax.new()
        |> Sagax.run(fn -> {:ok, "value"} end)
        |> Sagax.transaction(TestRepo, timeout: 1000)

      %Sagax{state: :ok, value: %{}} = Executer.execute(saga)

      assert_receive {:transaction, _fun, timeout: 1000}
    end

    test "rollbacks transaction on errors" do
      saga =
        Sagax.new()
        |> Sagax.run(fn -> {:error, "rollback!"} end)
        |> Sagax.transaction(TestRepo)

      %Sagax{state: :error, value: %{}} = Executer.execute(saga)
      assert_receive {:transaction, _fun, []}
      assert_receive {:rollback, _state}
    end

    test "runs compensations when error is occured", %{log: log} do
      saga =
        Sagax.new()
        |> Sagax.put("a", fn -> {:ok, "a"} end, fn -> Log.add(log, "a.comp") end)
        |> Sagax.put("b", fn -> {:error, "b"} end, fn -> Log.add(log, "b.comp") end)
        |> Sagax.transaction(TestRepo)

      %Sagax{state: :error, value: value, errors: errors} = Executer.execute(saga)

      assert value == %{"a" => "a"}
      assert errors === [%Sagax.Error{path: "b", error: "b"}]
      assert_log log, ["b.comp", "a.comp"]

      assert_receive {:transaction, _fun, []}
      assert_receive {:rollback, _state}
    end
  end
end
