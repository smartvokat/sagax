defmodule Sagax.ExecutorTest do
  alias Sagax
  alias Sagax.Executor, as: Executor
  alias Sagax.Test.Log
  alias Sagax.State, as: State

  import Sagax.Test.Assertions
  import Sagax.Test.Builder

  use ExUnit.Case

  setup do
    {:ok, log} = Log.start_link([])
    builder = new_builder(log: log)
    %{log: log, builder: builder}
  end

  describe "execute()" do
    test "executes a simple saga", %{builder: b, log: log} do
      state =
        Sagax.new()
        |> Sagax.run(effect(b, "a"))
        |> Sagax.run(effect(b, "b"))
        |> Sagax.run(effect(b, "c"))
        |> State.from_saga()
        |> Executor.execute()

      assert_state state, %{aborted?: false}
      assert_results state, ["a", "b", "c"]
      assert_log log, ["a", "b", "c"]
    end

    test "handles empty sagas", %{log: log} do
      state =
        Sagax.new()
        |> State.from_saga()
        |> Executor.execute()

      assert_state state, %{aborted?: false}
      assert_results state, []
      assert_log log, []
    end

    test "supports tagged results", %{builder: b, log: log} do
      state =
        Sagax.new()
        |> Sagax.run(effect(b, "a", tag: {:namespace, :tag}))
        |> Sagax.run(effect(b, "b", tag: :tag))
        |> Sagax.run(effect(b, "c", tag: "tag"))
        |> State.from_saga()
        |> Executor.execute()

      assert_state state, %{aborted?: false}
      assert_results state, [{"a", {:namespace, :tag}}, {"b", :tag}, {"c", "tag"}]
      assert_log log, ["a", "b", "c"]
    end

    test "executes a nested saga", %{builder: b, log: log} do
      nested_saga =
        Sagax.new()
        |> Sagax.run(effect(b, "b"))
        |> Sagax.run(effect(b, "c", results: ["a", "b"]))

      state =
        Sagax.new()
        |> Sagax.run(effect(b, "a"))
        |> Sagax.run(nested_saga)
        |> Sagax.run(effect(b, "d", results: ["a", "b", "c"]))
        |> State.from_saga()
        |> Executor.execute()

      assert_state state, %{aborted?: false}
      assert_results state, ["a", "b", "c", "d"]
      assert_log log, ["a", "b", "c", "d"]
    end

    test "executes effects in parallel", %{builder: b, log: log} do
      state =
        Sagax.new()
        |> Sagax.run(effect(b, "a"))
        |> Sagax.run_async(effect(b, "b", sync: false, results: ["a"]))
        |> Sagax.run_async(effect(b, "c", sync: false, results: ["a"]))
        |> Sagax.run(effect(b, "d"))
        |> State.from_saga()
        |> Executor.execute()

      assert_state state, %{aborted?: false}
      assert_results state, ["a", "b", "c", "d"]
      assert_log log, ["a", {"b", "c"}, "d"]
    end

    test "executes nested and parallel effects", %{builder: b, log: log} do
      nested_saga_1 =
        Sagax.new()
        |> Sagax.run(effect(b, "c", results: []))

      nested_saga_2 =
        Sagax.new()
        |> Sagax.run(effect(b, "f", results: ["a", "b", "c", "d", "e", "g", "h", "i"]))

      nested_saga_3 =
        Sagax.new()
        |> Sagax.run_async(effect(b, "g", results: ["a", "b", "c", "d"]))
        |> Sagax.run_async(effect(b, "h", results: ["a", "b", "c", "d"]))
        |> Sagax.run_async(effect(b, "i", results: ["a", "b", "c", "d"]))

      nested_saga_4 =
        Sagax.new()
        |> Sagax.run(effect(b, "d", results: ["a", "b", "c"]))
        |> Sagax.run_async(effect(b, "e", results: ["a", "b", "c", "d"]))
        |> Sagax.run_async(nested_saga_3)
        |> Sagax.run(nested_saga_2)

      state =
        Sagax.new()
        |> Sagax.run_async(effect(b, "a", results: []))
        |> Sagax.run_async(effect(b, "b", results: []))
        |> Sagax.run_async(nested_saga_1)
        |> Sagax.run(nested_saga_4)
        |> State.from_saga()
        |> Executor.execute()

      assert_state state, %{aborted?: false}
      assert_results state, ["a", "b", "c", "d", "e", "f", "g", "h", "i"]
      assert_log log, [{"a", "b", "c"}, ["d", {"e", {"g", "h", "i"}}, "f"]]
    end
  end

  describe "compensate()" do
    test "compensates a simple saga with :noop compensations", %{builder: b, log: log} do
      state =
        Sagax.new()
        |> Sagax.run(effect(b, "a"))
        |> Sagax.run(effect(b, "b"))
        |> Sagax.run(effect_error(b, "c"))
        |> State.from_saga()
        |> Executor.execute()

      assert_state state, %{aborted?: true}
      assert_results state, []
      assert_log log, ["a", "b", "c"]
    end

    test "compensates a simple saga", %{builder: b, log: log} do
      state =
        Sagax.new()
        |> Sagax.run(effect(b, "a"), compensation(b, "a"))
        |> Sagax.run(effect(b, "b"))
        |> Sagax.run(effect_error(b, "c"), compensation(b, "c"))
        |> State.from_saga()
        |> Executor.execute()

      assert_state state, %{aborted?: true}
      assert_results state, []
      assert_log log, ["a", "b", "c", "c.comp", "a.comp"]
    end

    test "compensates parallel effects in parallel", %{builder: b, log: log} do
      state =
        Sagax.new()
        |> Sagax.run_async(effect(b, "a"), compensation(b, "a"))
        |> Sagax.run_async(effect(b, "b"))
        |> Sagax.run_async(effect_error(b, "c"), compensation(b, "c"))
        |> State.from_saga()
        |> Executor.execute()

      assert_state state, %{aborted?: true}
      assert_results state, []
      assert_log log, [{"a", "b", "c"}, {"c.comp", "a.comp"}]
    end

    test "compensates a nested saga", %{builder: b, log: log} do
      nested_saga =
        Sagax.new()
        |> Sagax.run(effect(b, "b"), compensation(b, "b"))
        |> Sagax.run(effect(b, "c"), compensation(b, "c"))

      state =
        Sagax.new()
        |> Sagax.run(effect(b, "a"))
        |> Sagax.run(nested_saga)
        |> Sagax.run(effect_error(b, "d"), compensation(b, "d"))
        |> State.from_saga()
        |> Executor.execute()

      assert_state state, %{aborted?: true}
      assert_results state, []
      assert_log log, ["a", "b", "c", "d", "d.comp", "c.comp", "b.comp"]
    end
  end
end
