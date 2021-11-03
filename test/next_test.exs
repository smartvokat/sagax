defmodule Sagax.NextTest do
  alias Sagax.Next, as: Sagax
  alias Sagax.{Error, Executer, Op, TestRepo}
  alias Sagax.Test.Log

  require Sagax.Op

  use ExUnit.Case

  import Sagax.Test.Assertions

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

  describe "run()" do
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

      {:ok, %Sagax{state: :ok, value: %{}}} = Executer.execute(saga)

      assert_receive {:transaction, _fun, []}
    end

    test "accepts transaction options" do
      saga =
        Sagax.new()
        |> Sagax.run(fn -> {:ok, "value"} end)
        |> Sagax.transaction(TestRepo, timeout: 1000)

      {:ok, %Sagax{state: :ok, value: %{}}} = Executer.execute(saga)

      assert_receive {:transaction, _fun, timeout: 1000}
    end

    test "rollbacks transaction on errors" do
      saga =
        Sagax.new()
        |> Sagax.run(fn -> {:error, "rollback!"} end)
        |> Sagax.transaction(TestRepo)

      {:error, _errors} = Executer.execute(saga)
      assert_receive {:transaction, _fun, []}
      assert_receive {:rollback, _state}
    end

    test "runs compensations when error is occured", %{log: log} do
      saga =
        Sagax.new()
        |> Sagax.put("a", fn -> {:ok, "a"} end, fn -> Log.add(log, "a.comp") end)
        |> Sagax.put("b", fn -> {:error, "b"} end, fn -> Log.add(log, "b.comp") end)
        |> Sagax.transaction(TestRepo)

      {:error, [%Error{path: "b", error: "b"}]} = Executer.execute(saga)
      assert_log log, ["b.comp", "a.comp"]

      assert_receive {:transaction, _fun, []}
      assert_receive {:rollback, _state}
    end
  end
end
