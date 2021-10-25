defmodule Sagax.Next.State do
  @moduledoc """
  This struct holds the execution state of one or many sagas.
  """

  alias Sagax.Next, as: Sagax
  alias Sagax.State

  import Sagax.Op

  defstruct next: [],
            executed: [],
            suspended: [],
            values: %{},
            sagas: %{},
            opts: %{},
            execution: :ok

  @spec new(Sagax.t()) :: any
  def new(%Sagax{} = saga) do
    # We keep the reference to the saga to access `args` and `context`. To make
    # debugging a bit easier we clean the saga since all the important info is now
    # stored in `state`.
    sagas = Map.put(%{}, saga.id, %{saga | ops: []})

    # We will maintain a `value` per saga.
    values = Map.put(%{}, saga.id, saga.value)

    %State{next: Enum.reverse(saga.ops), values: values, sagas: sagas}
  end

  @doc """
  Applies the result of an operation depending on the operation type.
  """
  def apply(%State{} = state, operation, %Sagax{} = saga) when is_op(operation, :put) do
    # We keep the reference to the saga to access `args` and `context`. To make
    # debugging a bit easier we clean the saga since all the important info is now
    # stored in `state`.
    sagas = Map.put(state.sagas, saga.id, saga)

    # We will maintain a `value` per saga.
    key = Keyword.get(op(operation, :opts), :key)
    values = Map.put(state.values, saga.id, %{key => saga.value})

    opts =
      Enum.reduce(saga.ops, state.opts, fn op, acc ->
        Map.update(acc, op(op, :id), [key], &[key | &1])
      end)

    %{
      state
      | next: Enum.reverse(saga.ops) ++ state.next,
        values: values,
        sagas: sagas,
        opts: opts
    }
  end

  def apply(%State{values: values} = state, operation, {:ok, result})
      when is_op(operation, :put) do
    key = Keyword.get(op(operation, :opts), :key)
    saga_id = op(operation, :saga_id)
    outer_key = state.opts[op(operation, :id)]

    value = Map.get(values, saga_id, %{}) || %{}

    value =
      if outer_key do
        {_, value} =
          get_and_update_in(value, outer_key, fn existing_value ->
            if existing_value do
              {existing_value, Map.put(existing_value, key, result)}
            else
              {existing_value, %{key => result}}
            end
          end)

        value
      else
        Map.put(value, key, result)
      end

    %{state | values: Map.put(values, saga_id, value)}
  end

  def apply(%State{values: values} = state, operation, {:halt, result})
      when is_op(operation, :put) do
    key = Keyword.get(op(operation, :opts), :key)
    saga_id = op(operation, :saga_id)
    outer_key = state.opts[op(operation, :id)]

    value = Map.get(values, saga_id, %{}) || %{}

    value =
      if outer_key do
        {_, value} =
          get_and_update_in(value, outer_key, fn existing_value ->
            if existing_value do
              {existing_value, Map.put(existing_value, key, result)}
            else
              {existing_value, %{key => result}}
            end
          end)

        value
      else
        Map.put(value, key, result)
      end

    saga = state.sagas[saga_id]
    saga_op_ids = Enum.map(saga.ops, &op(&1, :id))

    next =
      Enum.reject(state.next, fn op ->
        Enum.member?(saga_op_ids, op(op, :id))
      end)

    %{state | values: Map.put(values, saga_id, value), next: next}
  end

  def apply(%State{values: values} = state, operation, {:error, result})
      when is_op(operation, :put) do
    key = Keyword.get(op(operation, :opts), :key)
    saga_id = op(operation, :saga_id)
    outer_key = state.opts[op(operation, :id)]
    value = Map.get(values, saga_id, %{}) || %{}

    value =
      if outer_key do
        {_, value} =
          get_and_update_in(value, outer_key, fn existing_value ->
            if existing_value do
              {existing_value, Map.put(existing_value, key, result)}
            else
              {existing_value, %{key => result}}
            end
          end)

        value
      else
        Map.put(value, key, result)
      end

    %{state | values: Map.put(values, saga_id, value), execution: :error}
  end

  def apply(%State{} = state, operation, {:error, _result}) when is_op(operation, :run) do
    %{state | execution: :error}
  end

  def apply(%State{} = state, operation, %Sagax{} = saga) when is_op(operation, :run) do
    sagas = Map.put(state.sagas, saga.id, saga)

    %{state | sagas: sagas, next: Enum.reverse(saga.ops) ++ state.next}
  end

  def apply(%State{} = state, operation, _result) when is_op(operation, :run), do: state

  def apply(_state, operation, result) do
    message = "Unexpected effect result for operation #{inspect(operation)}: #{inspect(result)}"
    %RuntimeError{message: message}
  end
end
