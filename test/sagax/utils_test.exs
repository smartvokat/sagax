defmodule Sagax.UtilsTest do
  alias Sagax.Utils
  alias Sagax.Test.Log
  alias Sagax.Executor

  import Sagax.Test.Assertions
  import Sagax.Test.Builder

  use ExUnit.Case

  setup do
    {:ok, log} = Log.start_link([])
    builder = new_builder(log: log)
    %{log: log, builder: builder}
  end

  describe "delete()" do
    test "removes a stage in a simple saga", %{builder: b, log: log} do
      saga =
        Sagax.new()
        |> Sagax.add(effect(b, "a"))
        |> Sagax.add(effect(b, "b"))
        |> Sagax.add(effect(b, "c"))

      saga = Utils.delete(saga, get_in(saga.queue, [Access.at(1), Access.elem(0)]))

      Executor.execute(saga)
      assert_log log, ["a", "c"]
    end

    test "removes an async stage", %{builder: b, log: log} do
      saga =
        Sagax.new()
        |> Sagax.add(effect(b, "a"))
        |> Sagax.add_async(effect(b, "b"))
        |> Sagax.add_async(effect(b, "c"))
        |> Sagax.add(effect(b, "d"))

      path = [Access.at(1), Access.at(1), Access.elem(0)]
      saga = Utils.delete(saga, get_in(saga.queue, path))

      Executor.execute(saga)
      assert_log log, ["a", "b", "d"]
    end
  end
end
