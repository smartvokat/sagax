defmodule Sagax.Test.Log do
  use Agent

  def start_link(_opts), do: Agent.start_link(fn -> [] end)

  def all(log), do: log |> Agent.get(& &1) |> Enum.reverse()

  def flatten(entries) when is_list(entries),
    do: Enum.reduce(entries, [], &(&2 ++ flatten(&1)))

  def flatten(entries) when is_tuple(entries),
    do: entries |> Tuple.to_list() |> Enum.reduce([], &(&2 ++ flatten(&1)))

  def flatten(entry), do: [entry]

  def size(entries), do: flatten(entries) |> length()

  def log(log, entry) do
    Agent.update(log, fn state -> [entry | state] end)
    entry
  end
end
