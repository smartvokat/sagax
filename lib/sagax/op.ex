defmodule Sagax.Op do
  @moduledoc false

  import Sagax.Executer

  @type effect :: any()
  @type compensation :: any()
  @type t() :: {atom(), keyword(), effect(), compensation()}

  @doc """
  Puts the result of `effect` under `key` in the final result of the saga.
  """
  @spec put(Sagax.t(), atom(), any(), any()) :: Sagax.t()
  def put(saga, key, effect, comp \\ :noop),
    do: %{saga | queue: [{:put, [key: key], effect, comp} | saga.queue]}

  @doc """
  Adds an effect to run as part of the saga.
  """
  @spec run(Sagax.t(), any(), any()) :: Sagax.t()
  def run(saga, effect, comp \\ :noop),
    do: %{saga | queue: [{:run, [], effect, comp} | saga.queue]}

  def apply(%Sagax{value: value} = saga, op, {:ok, result}) when is_op(op, :put) do
    key = Keyword.get(elem(op, 1), :key)
    %{saga | value: Map.put(value || %{}, key, result)}
  end

  def apply(%Sagax{} = saga, op, _) when is_op(op, :run), do: saga

  def apply(_saga, op, _) do
    message = "Unexpected result of effect in operation #{inspect(op)}"
    %RuntimeError{message: message}
  end
end
