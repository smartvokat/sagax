defmodule Sagax.Next.Utils do
  @doc """
  Generates an unique id.
  """
  def new_id(), do: "#{System.unique_integer([:positive])}"
end
