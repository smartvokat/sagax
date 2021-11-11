defmodule Sagax.Next.State do
  @moduledoc """
  This struct holds the execution state of one or many sagas.
  """

  alias Sagax.Next, as: Sagax
  alias Sagax.{State, Error}

  import Sagax.Op

  defstruct next: [],
            executed: [],
            suspended: [],
            values: %{},
            errors: [],
            sagas: %{},
            # Helps to track operation keys in order to put the value into right place
            # in case of nested sagas.
            ops_keys: %{},
            execution: :ok

  @spec new(Sagax.t()) :: any
  def new(%Sagax{} = saga) do
    # We keep the reference to the saga to access `args` and `context`.
    sagas = Map.put(%{}, saga.id, saga)

    # We will maintain a `value` per saga.
    values = Map.put(%{}, saga.id, saga.value)

    %State{next: Enum.reverse(saga.ops), values: values, sagas: sagas}
  end

  @doc """
  Applies the result of an operation depending on the operation type.
  """
  def apply(%State{} = state, operation, %Sagax{} = saga) when is_op(operation, :put) do
    sagas = Map.put(state.sagas, saga.id, saga)

    # We will maintain a `value` per saga.
    key = Keyword.get(op(operation, :opts), :key)
    values = Map.put(state.values, saga.id, %{key => saga.value})

    ops_keys =
      Enum.reduce(saga.ops, state.ops_keys, fn op, acc ->
        Map.update(acc, op(op, :id), [key], &[key | &1])
      end)

    %{
      state
      | next: Enum.reverse(saga.ops) ++ state.next,
        values: values,
        sagas: sagas,
        ops_keys: ops_keys
    }
  end

  def apply(%State{values: values} = state, operation, {:ok, result})
      when is_op(operation, :put) do
    key = Keyword.get(op(operation, :opts), :key)
    saga_id = op(operation, :saga_id)
    outer_key = state.ops_keys[op(operation, :id)]

    value = Map.get(values, saga_id, %{}) || %{}
    value = update_value(value, outer_key, key, result)

    %{state | values: Map.put(values, saga_id, value)}
  end

  def apply(%State{values: values} = state, operation, {:halt, result})
      when is_op(operation, :put) do
    key = Keyword.get(op(operation, :opts), :key)
    saga_id = op(operation, :saga_id)
    outer_key = state.ops_keys[op(operation, :id)]

    value = Map.get(values, saga_id, %{}) || %{}
    value = update_value(value, outer_key, key, result)

    saga = state.sagas[saga_id]
    saga_op_ids = Enum.map(saga.ops, &op(&1, :id))

    next =
      Enum.reject(state.next, fn op ->
        Enum.member?(saga_op_ids, op(op, :id))
      end)

    %{state | values: Map.put(values, saga_id, value), next: next}
  end

  def apply(%State{errors: errors} = state, operation, {:error, result})
      when is_op(operation, :put) do
    key = Keyword.get(op(operation, :opts), :key)
    outer_key = state.ops_keys[op(operation, :id)]

    errors = [%Error{path: outer_key || key, error: result} | errors]

    %{state | errors: errors, execution: :error}
  end

  def apply(%State{errors: errors} = state, operation, {:error, result})
      when is_op(operation, :run) do
    errors = [%Error{error: result} | errors]

    %{state | errors: errors, execution: :error}
  end

  def apply(%State{} = state, operation, %Sagax{} = saga) when is_op(operation, :run) do
    sagas = Map.put(state.sagas, saga.id, saga)

    %{state | sagas: sagas, next: Enum.reverse(saga.ops) ++ state.next}
  end

  def apply(_state, _operation, {:raise, {exception, stacktrace}}) do
    reraise(exception, stacktrace)
  end

  def apply(%State{} = state, operation, _result) when is_op(operation, :run), do: state

  # Iterating over compensations that have their result as nil, so we don't need to store
  # the `result` to the `errors` list.
  def apply(%State{execution: :error} = state, _operation, result) when is_nil(result) do
    state
  end

  def apply(_state, operation, result) do
    message = "Unexpected effect result for operation #{inspect(operation)}: #{inspect(result)}"
    %RuntimeError{message: message}
  end

  defp update_value(value, outer_key, key, result) when is_nil(outer_key) do
    Map.put(value, key, result)
  end

  defp update_value(value, outer_key, key, result) do
    {_, value} =
      get_and_update_in(value, outer_key, fn existing_value ->
        if existing_value do
          {existing_value, Map.put(existing_value, key, result)}
        else
          {existing_value, %{key => result}}
        end
      end)

    value
  end
end
