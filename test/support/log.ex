defmodule Sagax.Test.Log do
  use Agent

  def start_link(_opts), do: Agent.start_link(fn -> [] end)

  def all(log), do: Agent.get(log, & &1) |> Enum.reverse()

  def sync(log, entry) do
    Agent.update(log, fn state -> [entry | state] end)
    entry
  end
end
