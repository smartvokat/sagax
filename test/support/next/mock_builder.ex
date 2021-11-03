defmodule Sagax.Next.Test.MockBuilder do
  alias Sagax.Next, as: Sagax

  use Sagax.Builder

  defp new(args, context, opts) do
    Sagax.new(args: args, context: context, opts: opts)
    |> Sagax.put("a", fn -> {:ok, "a"} end)
    |> Sagax.put("b", fn -> {:ok, "b"} end)
  end
end
