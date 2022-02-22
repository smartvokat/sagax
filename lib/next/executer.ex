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
      |> execute_state(saga.opts)

    context =
      Enum.reduce(state.sagas, %{}, fn {_, saga}, acc ->
        Map.merge(acc, saga.context || %{})
      end)

    %{saga | value: state.values, errors: state.errors, state: state.execution, context: context}
  end

  defp do_execute(%State{next: []} = state), do: state

  defp do_execute(%State{next: [operation | next]} = state) do
    saga_id = op(operation, :saga_id)
    saga = Map.get(state.sagas, saga_id)

    path = State.build_key_path(state, saga, [])

    value =
      cond do
        state.values == %{} ->
          nil

        path != [] ->
          get_in(state.values, path)

        true ->
          state.values
      end

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
      %State{execution: execution} = state when execution in [:ok, :halt] ->
        do_execute(%{state | executed: [operation | state.executed]})

      %State{execution: :error} = state ->
        state = %{state | executed: [operation | state.executed]}

        do_compensate(state)
    end
  end

  defp do_compensate(%State{executed: []} = state), do: state

  defp do_compensate(%State{executed: [operation | executed]} = state) when is_noop(operation) do
    do_compensate(%{state | executed: executed})
  end

  defp do_compensate(%State{executed: [operation | executed]} = state) do
    saga_id = op(operation, :saga_id)
    saga = Map.get(state.sagas, saga_id)
    value = Map.get(state.values, saga_id)
    comp = op(operation, :comp)

    comp_result =
      cond do
        is_function(comp) ->
          safe_apply(comp, value, saga)

        true ->
          nil
      end

    state = %{state | executed: executed}
    state = State.apply(state, operation, comp_result)

    do_compensate(state)
  end

  defp safe_apply(func, value, saga) do
    try do
      apply_func(func, value, saga.args, saga.context)
    rescue
      exception ->
        {:raise, {exception, __STACKTRACE__}}
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

  defp execute_state(state, saga_opts) do
    if saga_opts[:execute_in_transaction] do
      # TODO validate options here, i.e. repo must be provided here.
      repo = saga_opts[:repo]
      transaction_opts = saga_opts[:transaction_opts]

      execute_in_transaction(state, repo, transaction_opts)
    else
      do_execute(state)
    end
  end

  defp execute_in_transaction(state, repo, transaction_opts) do
    fn ->
      case do_execute(state) do
        %State{execution: :error} = state ->
          repo.rollback(state)

        state ->
          state
      end
    end
    |> repo.transaction(transaction_opts)
    |> case do
      {:ok, {:error, state}} ->
        state

      {:error, state} ->
        state

      {:ok, %State{} = state} ->
        state
    end
  end
end
