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
            execution: :ok

  @spec new(Sagax.t()) :: any
  def new(%Sagax{} = saga) do
    # We keep the reference to the saga to access `args` and `context`.
    sagas = Map.put(%{}, saga.id, saga)

    %State{next: Enum.reverse(saga.ops), sagas: sagas}
  end

  @doc """
  Applies the result of an operation depending on the operation type.
  """
  def apply(%State{} = state, operation, %Sagax{} = saga) when is_op(operation, :put) do
    key = Keyword.get(op(operation, :opts), :key)
    parent_saga_id = op(operation, :saga_id)

    saga =
      %{
        saga
        | parent_saga_id: parent_saga_id,
          nested_key: key
      }
    sagas = Map.put(state.sagas, saga.id, saga)

    # Put future values of nested saga(s) into corresponding keys of the parent saga(s).
    #
    # Example:
    # > Sagax.put("a" => Sagax.put("b" => Sagax.put("c" => {:ok, "c"})
    # should generate at this stage
    # %{"a" => %{"b" => %{"c" => nil}}}
    # since "c" op has not been executed yet, the value is `nil`.
    path = build_key_path(state, saga, [])

    values =
      if length(path) > 1 do
        [key | path] = Enum.reverse(path)
        put_in(state.values, Enum.reverse(path), %{key => saga.value})
      else
        Map.put(state.values, key, saga.value)
      end

    %{
      state
      | next: Enum.reverse(saga.ops) ++ state.next,
        values: values,
        sagas: sagas
    }
  end

  def apply(%State{sagas: sagas} = state, operation, {:ok, result, context})
      when is_op(operation, :put) do
    key = Keyword.get(op(operation, :opts), :key)
    saga_id = op(operation, :saga_id)
    saga = state.sagas[saga_id]
    saga_context = Map.merge(saga.context || %{}, context)
    saga = Map.put(saga, :context, saga_context)
    sagas = Map.put(sagas, saga_id, saga)

    values = update_values(state, saga, key, result)

    %{state | values: values, sagas: sagas}
  end

  def apply(%State{} = state, operation, {:ok, result})
      when is_op(operation, :put) do
    key = Keyword.get(op(operation, :opts), :key)
    saga_id = op(operation, :saga_id)
    saga = state.sagas[saga_id]

    values = update_values(state, saga, key, result)

    %{state | values: values}
  end

  def apply(%State{sagas: sagas} = state, operation, {:halt, result, context})
      when is_op(operation, :put) do
    key = Keyword.get(op(operation, :opts), :key)
    saga_id = op(operation, :saga_id)
    saga = state.sagas[saga_id]
    saga_context = Map.merge(saga.context || %{}, context)
    saga = Map.put(saga, :context, saga_context)
    sagas = Map.put(sagas, saga_id, saga)

    values = update_values(state, saga, key, result)

    saga_op_ids = Enum.map(saga.ops, &op(&1, :id))

    next =
      Enum.reject(state.next, fn op ->
        Enum.member?(saga_op_ids, op(op, :id))
      end)

    %{state | values: values, next: next, sagas: sagas, execution: :halt}
  end

  def apply(%State{} = state, operation, {:halt, result})
      when is_op(operation, :put) do
    key = Keyword.get(op(operation, :opts), :key)
    saga_id = op(operation, :saga_id)
    saga = state.sagas[saga_id]

    values = update_values(state, saga, key, result)
    saga_op_ids = Enum.map(saga.ops, &op(&1, :id))

    next =
      Enum.reject(state.next, fn op ->
        Enum.member?(saga_op_ids, op(op, :id))
      end)

    %{state | values: values, next: next, execution: :halt}
  end

  def apply(%State{errors: errors} = state, operation, {:error, result})
      when is_op(operation, :put) do
    key = Keyword.get(op(operation, :opts), :key)

    errors = [%Error{path: key, error: result} | errors]

    %{state | errors: errors, execution: :error}
  end

  def apply(%State{sagas: sagas} = state, operation, {:halt, _result, context})
      when is_op(operation, :run) do
    saga_id = op(operation, :saga_id)
    saga = state.sagas[saga_id]
    saga_context = Map.merge(saga.context || %{}, context)
    saga = Map.put(saga, :context, saga_context)
    sagas = Map.put(sagas, saga_id, saga)
    saga_op_ids = Enum.map(saga.ops, &op(&1, :id))

    next =
      Enum.reject(state.next, fn op ->
        Enum.member?(saga_op_ids, op(op, :id))
      end)

    %{state | next: next, sagas: sagas, execution: :halt}
  end

  def apply(%State{} = state, operation, {:halt, _result})
      when is_op(operation, :run) do
    saga_id = op(operation, :saga_id)
    saga = state.sagas[saga_id]
    saga_op_ids = Enum.map(saga.ops, &op(&1, :id))

    next =
      Enum.reject(state.next, fn op ->
        Enum.member?(saga_op_ids, op(op, :id))
      end)

    %{state | next: next, execution: :halt}
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

  def build_key_path(state, %{parent_saga_id: parent_saga_id, nested_key: nested_key} = _saga, path) when not is_nil(nested_key) do
    path = [nested_key | path]
    parent_saga = state.sagas[parent_saga_id]

    build_key_path(state, parent_saga, path)
  end

  def build_key_path(_state, _saga, path), do: path

  def update_values(%State{} = state, saga, key, result) do
    if saga.parent_saga_id do
      path = build_key_path(state, saga, [])
      update_in(state.values, path, &(Map.merge(&1 || %{}, %{key => result})))
    else
      Map.put(state.values, key, result)
    end
  end
end
