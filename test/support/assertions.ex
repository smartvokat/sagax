defmodule Sagax.Test.Assertions do
  alias Sagax.Test.Log

  import ExUnit.Assertions

  defmacro assert_state(state, pattern) do
    quote do
      if match?({%ExUnit.AssertionError{}, _}, unquote(state).last_result) do
        {error, stacktrace} = unquote(state).last_result
        reraise error, stacktrace
      end

      assert unquote(pattern) = unquote(state)
    end
  end

  defmacro assert_log(log, entries) do
    quote bind_quoted: [log: log, entries: entries] do
      logs = Log.all(log)

      assert Log.size(logs) == Log.size(logs),
        message: "Expected #{Log.size(logs)} log entries but got #{Log.size(entries)}",
        left: logs,
        right: entries

      try do
        compare_log(logs, entries, 0, 0, [], [])
      rescue
        e in ExUnit.AssertionError ->
          reraise(%{e | left: logs, right: entries}, __STACKTRACE__)
      end
    end
  end

  defmacro assert_results(left, results) do
    quote bind_quoted: [left: left, results: results] do
      left = if match?(%Sagax.State{}, left), do: Map.values(left.results), else: Map.values(left)

      assert length(left) == length(results),
        message: "Expected #{length(results)} results but got #{length(left)}",
        left: left,
        right: results

      Enum.each(results, fn right ->
        assert Enum.any?(left, &(&1 === right)),
          message: "Expected results to contain the result #{inspect(right)}",
          left: left,
          right: results
      end)
    end
  end

  def compare_log([], [], _, _, _, _), do: :ok

  def compare_log(left, [], li, _, lp, _) when length(left) > 0 do
    raise ExUnit.AssertionError,
      message: "Expected no more log entries at left path #{path(li, lp)}"
  end

  def compare_log([], right, li, ri, lp, rp) when length(right) > 0 do
    raise ExUnit.AssertionError,
      message:
        "Expected log to continue at left path #{path(li, lp)} " <>
          "with right path #{path(ri, rp)}"
  end

  # List indicate that the logs should be sequential
  def compare_log([left | _], [right | _], li, ri, lp, rp) when is_list(right),
    do: compare_log(left, right, 0, 0, lp ++ [li], rp ++ [ri])

  # Tuples indicate that the logs should be parallel
  def compare_log(left, [right | rt], li, ri, lp, rp) when is_tuple(right) do
    values = Log.flatten(right)
    breaks = if length(rt) > 0, do: peek(hd(rt), false), else: []

    remaining_values =
      Enum.reduce_while(left, values, fn val, acc ->
        cond do
          Enum.member?(breaks, val) -> {:halt, acc}
          Enum.member?(values, val) -> {:cont, List.delete(acc, val)}
          true -> {:cont, acc}
        end
      end)

    if length(remaining_values) > 0 do
      raise ExUnit.AssertionError,
        message:
          "Expected log at left path #{path(li, lp)}..#{li + length(values)} " <>
            "to contain entries #{inspect(remaining_values)}"
    end

    compare_log(Enum.slice(left, length(values)..-1), rt, li + length(values), ri + 1, lp, rp)
  end

  # When its neither a list nor a tuple we should simply compare the value
  def compare_log([left | lt], [right | rt], li, ri, lp, rp) do
    assert left === right,
      message:
        "Expected value at left path #{path(li, lp)} to match value at right path #{path(ri, rp)}"

    compare_log(lt, rt, li + 1, ri + 1, lp, rp)
  end

  def compare_log(left, [right | _], li, ri, lp, rp) do
    assert left === right,
      message:
        "Expected value at left path #{path(li, lp)} to match value at right path #{path(ri, rp)}"
  end

  defp path(idx, path), do: "/" <> ([Enum.join(path, "/"), idx] |> Enum.join("/"))

  defp peek(val, false) when is_list(val), do: val |> hd() |> peek(true)

  defp peek(val, _) when is_tuple(val) or is_list(val),
    do: Log.flatten(val) |> Enum.reduce([], &(&2 ++ peek(&1, true)))

  defp peek(val, _), do: [val]
end
