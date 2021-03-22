defmodule Sagax.Executer do
  @doc """
  Executes a saga.
  """
  @callback execute(Sagax.t()) :: Sagax.t()

  defguard is_op(op) when is_tuple(op)
  defguard is_op(op, name) when elem(op, 0) == name
end
