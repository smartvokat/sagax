defmodule Sagax.Next.Executer do
  alias Sagax.Next, as: Sagax
  alias Sagax.State

  import Sagax.Op

  @doc """
  Executes a saga.
  """
  def execute(%Sagax{} = saga) do
    state =
      saga
      |> State.new()
      |> do_execute()

    values =
      Enum.reduce(state.values, %{}, fn {_saga_id, saga_values}, acc ->
        if saga_values do
          Map.merge(acc, saga_values)
        else
          acc
        end
      end)

    %{saga | value: values, state: state.execution}
  end

  defp do_execute(%State{next: []} = state), do: state

  defp do_execute(%State{next: [operation | next]} = state) do
    saga_id = op(operation, :saga_id)
    saga = Map.get(state.sagas, saga_id)
    value = Map.get(state.values, saga_id)
    effect = op(operation, :effect)

    result =
      cond do
        is_function(effect) ->
          safe_apply(effect, value, saga)

        %Sagax{} ->
          effect

        true ->
          nil
      end

    case State.apply(%{state | next: next}, operation, result) do
      %State{execution: :ok} = state ->
        do_execute(%{state | executed: [operation | state.executed]})

      %State{execution: :error} = state ->
        state = %{state | executed: [operation | state.executed]}

        do_compensate(state)
    end
  end

  # defp do_execute(%State{} = state, operation) when is_op(operation, :finalize) do
  # end

  # defp do_execute(%State{} = state, operation) when is_op(operation, :finalize) do
  # end

  defp do_compensate(%State{executed: []} = state), do: state

  defp do_compensate(%State{executed: [operation | executed]} = state) when is_noop(operation) do
    do_compensate(%{state | executed: executed})
  end

  defp do_compensate(%State{executed: [operation | executed]} = state) do
    saga_id = op(operation, :saga_id)
    saga = Map.get(state.sagas, saga_id)
    value = Map.get(state.values, saga_id)
    comp = op(operation, :comp)

    cond do
      is_function(comp) ->
        safe_apply(comp, value, saga)

      true ->
        nil
    end

    do_compensate(%{state | executed: executed})
  end

  defp safe_apply(func, value, saga) do
    task =
      fn ->
        try do
          apply_func(func, value, saga.args, saga.context)
        rescue
          exception ->
            {:raise, {exception, __STACKTRACE__}}
        end
      end
      |> task_module().async()

    timeout = Keyword.get(saga.opts, :timeout, 5000)

    case task_module().yield(task, timeout) || task_module().shutdown(task, timeout) do
      {:ok, result} ->
        result

      nil ->
        {:exit, :timeout}
    end
  end

  def apply_func(effect, value, args, context) do
    cond do
      is_function(effect, 0) ->
        apply(effect, [])

      is_function(effect, 1) ->
        apply(effect, [value])

      is_function(effect, 2) ->
        apply(effect, [value, args])

      is_function(effect, 3) ->
        apply(effect, [value, args, context])

      true ->
        raise ArgumentError,
              "Expected a function with arity 0, 1, 2 or 3 in effect " <>
                "#{inspect(effect)}"
    end
  end

  defp task_module do
    Application.get_env(:sagax, :task_module, Task)
  end
end
