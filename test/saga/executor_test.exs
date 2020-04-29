defmodule Sagax.ExecutorTest do
  alias Sagax
  alias Sagax.Executor
  alias Sagax.Test.Log

  import Sage.Test.Assertions
  import Sagax.Test.Builder

  use ExUnit.Case

  setup do
    {:ok, log} = Log.start_link([])
    %{log: log}
  end

  describe "execute() with sync stages" do
    test "executes a single stage", %{log: log} do
      state =
        Sagax.new()
        |> Sagax.run(fn _, _, _ -> {:ok, Log.sync(log, "a")} end)
        |> Executor.execute(%{})

      assert %{aborted?: false, results: ["a"]} = state
      assert Log.all(log) == ["a"]
    end

    test "supports stage tagging", %{log: log} do
      state =
        Sagax.new()
        |> Sagax.run(fn _, _, _ -> {:ok, "tag", Log.sync(log, "a")} end)
        |> Sagax.run(fn _, _, _ -> {:ok, {:namespace, :tag}, Log.sync(log, "b")} end)
        |> Executor.execute(%{})

      assert %{aborted?: false, results: [{{:namespace, :tag}, "b"}, {"tag", "a"}]} = state
      assert Log.all(log) == ["a", "b"]
    end

    test "executes sequential stages", %{log: log} do
      state =
        Sagax.new()
        |> Sagax.run(fn _, _, _ -> {:ok, Log.sync(log, "a")} end)
        |> Sagax.run(fn _, _, _ -> {:ok, Log.sync(log, "b")} end)
        |> Executor.execute(%{})

      assert %{aborted?: false, results: ["b", "a"]} = state
      assert Log.all(log) == ["a", "b"]
    end

    test "handles an error response in an effect", %{log: log} do
      state =
        Sagax.new()
        |> Sagax.run(fn _, _, _ -> {:error, Log.sync(log, "error")} end)
        |> Executor.execute(%{})

      assert %{aborted?: true, last_result: "error"} = state
      assert Log.all(log) == ["error"]
    end

    test "handles an exception in an effect", %{log: log} do
      state =
        Sagax.new()
        |> Sagax.run(fn _, _, _ -> raise "Error" end)
        |> Executor.execute(%{})

      assert Log.all(log) == []
      assert %{aborted?: true, last_result: {%RuntimeError{message: "Error"}, _}} = state
    end

    test "compensates when an effect returns an error response", %{log: log} do
      b = new_builder(log: log, args: %{foo: "bar"}, context: %{con: "text"})

      state =
        Sagax.new()
        |> Sagax.run(sync_effect(b, "a"), sync_comp(b, "a"))
        |> Sagax.run(sync_effect_error(b, "b", results: ["a"]), sync_comp(b, "b", results: ["a"]))
        |> Executor.execute(%{foo: "bar"}, %{con: "text"})

      assert %{aborted?: true, last_result: "b"} = state
      assert Log.all(log) == ["a", "b", "b.comp", "a.comp"]
    end
  end

  describe "execute() with nested sagas" do
    test "executes nested sagas", %{log: log} do
      b = new_builder(log: log)

      state =
        Sagax.new()
        |> Sagax.run(sync_effect(b, "a"))
        |> Sagax.run(Sagax.run(Sagax.new(), sync_effect(b, "b")))
        |> Sagax.run(Sagax.run(Sagax.new(), Sagax.run(Sagax.new(), sync_effect(b, "c"))))
        |> Executor.execute(%{})

      assert_state state, %{results: [[["c"]], ["b"], "a"]}
      assert Log.all(log) == ["a", "b", "c"]
    end
  end
end
