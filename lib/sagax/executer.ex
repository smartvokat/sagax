defmodule Sagax.Executor do
  alias Sagax.State

  def execute(%State{queue: []} = state), do: state
  def execute(%State{} = state), do: do_execute(state) |> next()

  def compensate(%State{stack: []} = state), do: state
  def compensate(%State{} = state), do: do_compensate(state) |> next()

  def next(%State{aborted?: false} = state), do: execute(state)
  def next(%State{aborted?: true} = state), do: compensate(state)

  defp do_execute(%State{queue: [{%Sagax{} = saga, _comp, _opts} | _tail]} = state) do
    saga
    |> State.from_saga(state.args, state.context)
    |> Map.put(:results, state.results)
    |> execute()
    |> handle_execute_result(state)
  end

  defp do_execute(%State{queue: [effects | tail]} = state) when is_list(effects) do
    inner_state =
      effects
      |> Task.async_stream(
        fn effect -> do_execute(%{state | queue: [effect]}) end,
        state.opts
      )
      |> Enum.reduce_while(%{state | results: %{}}, fn
        {:ok, %{aborted?: true} = result_state}, acc ->
          {:halt,
           %{
             acc
             | aborted?: true,
               stack: acc.stack ++ result_state.stack,
               results: Map.merge(acc.results, result_state.results),
               last_result: result_state.last_result
           }}

        {:ok, result_state}, acc ->
          {:cont,
           %{
             acc
             | stack: acc.stack ++ result_state.stack,
               results: Map.merge(acc.results, result_state.results)
           }}
      end)

    %{
      state
      | aborted?: inner_state.aborted?,
        queue: tail,
        stack: [inner_state.stack | state.stack],
        results: Map.merge(state.results, inner_state.results),
        last_result: inner_state.last_result || state.last_result
    }
  end

  defp do_execute(%State{queue: [{effect, _comp, opts} | _tail]} = state) do
    effect
    |> safe_apply([state.results, state.args, state.context], opts, state.opts)
    |> handle_execute_result(state)
  end

  def do_compensate(%State{stack: [items | tail]} = state) when is_list(items) do
    inner_state =
      items
      |> Task.async_stream(
        fn item -> {elem(item, 0), do_compensate(%{state | stack: [item]})} end,
        state.opts
      )
      |> Enum.reduce(state, fn {:ok, {effect, _}}, acc ->
        %{acc | results: Map.delete(acc.results, effect)}
      end)

    %{inner_state | stack: tail}
  end

  def do_compensate(%State{stack: [{%Sagax{} = saga, _comp, _opts} | _tail]} = state) do
    %{state | stack: saga.queue}
    |> compensate()
    |> handle_compensate_result(state)
  end

  def do_compensate(%State{stack: [{_, :noop, _opts} | _tail]} = state),
    do: handle_compensate_result(:ok, state)

  def do_compensate(%State{stack: [{effect, comp, opts} | _tail], results: results} = state) do
    result = Map.get(results, effect)

    comp
    |> safe_apply([result, results, state.args, state.context], opts, state.opts)
    |> handle_compensate_result(state)
  end

  defp handle_execute_result(:ok, %{queue: [item | queue]} = state),
    do: %{
      state
      | queue: queue,
        stack: [item | state.stack],
        results: Map.put(state.results, elem(item, 0), nil)
    }

  defp handle_execute_result({:ok, value}, %{queue: [item | queue]} = state),
    do: %{
      state
      | queue: queue,
        stack: [item | state.stack],
        results: Map.put(state.results, elem(item, 0), value)
    }

  defp handle_execute_result({:ok, value, tag}, %{queue: [item | queue]} = state)
       when is_binary(tag) or is_atom(tag) or is_tuple(tag),
       do: %{
         state
         | queue: queue,
           stack: [item | state.stack],
           results: Map.put(state.results, elem(item, 0), {value, tag})
       }

  defp handle_execute_result(
         %State{aborted?: false, last_result: last_result, results: results},
         %{queue: [item | queue]} = state
       ),
       do: %{
         state
         | queue: queue,
           stack: [item | state.stack],
           results: Map.merge(state.results, results),
           last_result: last_result
       }

  defp handle_execute_result(
         %State{aborted?: true, last_result: last_result, results: results},
         %{queue: [item | _]} = state
       ),
       do: %{
         state
         | aborted?: true,
           stack: [item | state.stack],
           results: Map.merge(state.results, results),
           last_result: last_result
       }

  defp handle_execute_result({:error, error_or_result}, %{queue: [item | queue]} = state),
    do: %{
      state
      | aborted?: true,
        queue: queue,
        stack: [item | state.stack],
        results: Map.put(state.results, elem(item, 0), error_or_result),
        last_result: error_or_result
    }

  defp handle_execute_result(
         {:raise, {_exception, _stacktrace} = exception},
         %{queue: [item | queue]} = state
       ),
       do: %{
         state
         | aborted?: true,
           queue: queue,
           stack: [item | state.stack],
           results: Map.put(state.results, elem(item, 0), {exception, nil}),
           last_result: exception
       }

  defp handle_compensate_result(result, %{stack: [item | stack], results: results} = state) do
    case result do
      :ok ->
        %{state | stack: stack, results: Map.delete(results, elem(item, 0))}

      {:error, _error_or_result} ->
        # TODO: Implement an on_error handler
        raise "Panic"

      {:raise, {exception, stacktrace}} ->
        # TODO: Implement an on_error handler
        reraise(exception, stacktrace)

      # {:exit, :timeout} ->
      #   compensate(%{
      #     state
      #     | aborted?: true,
      #       stack: [item | state.stack],
      #       results: [{nil, nil} | state.results]
      #       last_result: nil
      #   })

      %State{results: results} ->
        %{state | stack: stack, results: results}
    end
  end

  defp safe_apply(func, args, opts, saga_opts) do
    task =
      fn ->
        try do
          apply(func, args ++ [opts])
        rescue
          exception ->
            {:raise, {exception, __STACKTRACE__}}
        end
      end
      |> Task.async()

    timeout = Keyword.get(saga_opts, :timeout, 5000)
    timeout = Keyword.get(opts, :timeout, timeout)

    case Task.yield(task, timeout) || Task.shutdown(task, timeout) do
      {:ok, result} ->
        result

      nil ->
        {:exit, :timeout}
    end
  end
end
