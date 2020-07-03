defmodule Sagax.ExecutorTest do
  alias Sagax
  alias Sagax.Executor, as: Executor
  alias Sagax.Test.Log

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
      saga =
        Sagax.new()
        |> Sagax.add(effect(b, "a"))
        |> Sagax.add(effect(b, "b"))
        |> Sagax.add(effect(b, "c"))
        |> Executor.execute()

      assert_saga saga, %{state: :ok}
      assert_saga_results saga, ["a", "b", "c"]
      assert_log log, ["a", "b", "c"]
    end

    test "handles empty sagas", %{log: log} do
      saga = Executor.execute(Sagax.new())

      assert_saga saga, %{state: :ok}
      assert_saga_results saga, []
      assert_log log, []
    end

    test "supports tagged results", %{builder: b, log: log} do
      saga =
        Sagax.new()
        |> Sagax.add(effect(b, "a", tag: {:namespace, :tag}))
        |> Sagax.add(effect(b, "b", tag: :tag))
        |> Sagax.add(effect(b, "c", tag: "tag"))
        |> Executor.execute()

      assert_saga saga, %{state: :ok}
      assert_saga_results saga, [{"a", {:namespace, :tag}}, {"b", :tag}, {"c", "tag"}]
      assert_log log, ["a", "b", "c"]
    end

    test "executes a nested saga", %{builder: b, log: log} do
      nested_saga =
        Sagax.new()
        |> Sagax.add(effect(b, "b"))
        |> Sagax.add(effect(b, "c", results: ["a", "b"]))

      saga =
        Sagax.new()
        |> Sagax.add(effect(b, "a"))
        |> Sagax.add(nested_saga)
        |> Sagax.add(effect(b, "d", results: ["a", "b", "c"]))
        |> Executor.execute()

      assert_saga saga, %{state: :ok}
      assert_saga_results saga, ["a", "b", "c", "d"]
      assert_log log, ["a", "b", "c", "d"]
    end

    test "executes effects in parallel", %{builder: b, log: log} do
      saga =
        Sagax.new()
        |> Sagax.add(effect(b, "a"))
        |> Sagax.add_async(effect(b, "b", sync: false, results: ["a"]))
        |> Sagax.add_async(effect(b, "c", sync: false, results: ["a"]))
        |> Sagax.add(effect(b, "d"))
        |> Executor.execute()

      assert_saga saga, %{state: :ok}
      assert_saga_results saga, ["a", "b", "c", "d"]
      assert_log log, ["a", {"b", "c"}, "d"]
    end

    test "executes nested and parallel effects", %{builder: b, log: log} do
      nested_saga_1 =
        Sagax.new()
        |> Sagax.add(effect(b, "c", results: []))

      nested_saga_2 =
        Sagax.new()
        |> Sagax.add(effect(b, "f", results: ["a", "b", "c", "d", "e", "g", "h", "i"]))

      nested_saga_3 =
        Sagax.new()
        |> Sagax.add_async(effect(b, "g", results: ["a", "b", "c", "d"]))
        |> Sagax.add_async(effect(b, "h", results: ["a", "b", "c", "d"]))
        |> Sagax.add_async(effect(b, "i", results: ["a", "b", "c", "d"]))

      nested_saga_4 =
        Sagax.new()
        |> Sagax.add(effect(b, "d", results: ["a", "b", "c"]))
        |> Sagax.add_async(effect(b, "e", results: ["a", "b", "c", "d"]))
        |> Sagax.add_async(nested_saga_3)
        |> Sagax.add(nested_saga_2)

      saga =
        Sagax.new()
        |> Sagax.add_async(effect(b, "a", results: []))
        |> Sagax.add_async(effect(b, "b", results: []))
        |> Sagax.add_async(nested_saga_1)
        |> Sagax.add(nested_saga_4)
        |> Executor.execute()

      assert_saga saga, %{state: :ok}
      assert_saga_results saga, ["a", "b", "c", "d", "e", "f", "g", "h", "i"]
      assert_log log, [{"a", "b", "c"}, ["d", {"e", {"g", "h", "i"}}, "f"]]
    end
  end

  describe "compensate()" do
    test "compensates a simple saga with :noop compensations", %{builder: b, log: log} do
      saga =
        Sagax.new()
        |> Sagax.add(effect(b, "a"))
        |> Sagax.add(effect(b, "b"))
        |> Sagax.add(effect_error(b, "c"))
        |> Executor.execute()

      assert_saga saga, %{state: :error}
      assert_saga_results saga, []
      assert_log log, ["a", "b", "c"]
    end

    test "compensates a simple saga", %{builder: b, log: log} do
      saga =
        Sagax.new()
        |> Sagax.add(effect(b, "a"), compensation(b, "a"))
        |> Sagax.add(effect(b, "b"))
        |> Sagax.add(effect_error(b, "c"), compensation(b, "c"))
        |> Executor.execute()

      assert_saga saga, %{state: :error}
      assert_saga_results saga, []
      assert_log log, ["a", "b", "c", "c.comp", "a.comp"]
    end

    test "compensates parallel effects in parallel", %{builder: b, log: log} do
      saga =
        Sagax.new()
        |> Sagax.add_async(effect(b, "a"), compensation(b, "a"))
        |> Sagax.add_async(effect(b, "b"))
        |> Sagax.add_async(effect_error(b, "c"), compensation(b, "c"))
        |> Executor.execute()

      assert_saga saga, %{state: :error}
      assert_saga_results saga, []
      assert_log log, [{"a", "b", "c"}, {"c.comp", "a.comp"}]
    end

    test "compensates a nested saga", %{builder: b, log: log} do
      nested_saga =
        Sagax.new()
        |> Sagax.add(effect(b, "b"), compensation(b, "b"))
        |> Sagax.add(effect(b, "c"), compensation(b, "c"))

      saga =
        Sagax.new()
        |> Sagax.add(effect(b, "a"))
        |> Sagax.add(nested_saga)
        |> Sagax.add(effect_error(b, "d"), compensation(b, "d"))
        |> Executor.execute()

      assert_saga saga, %{state: :error}
      assert_saga_results saga, []
      assert_log log, ["a", "b", "c", "d", "d.comp", "c.comp", "b.comp"]
    end
  end
end
