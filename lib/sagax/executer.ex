defmodule Sagax.Executor do
  def execute(%Sagax{queue: []} = saga), do: saga
  def execute(%Sagax{} = saga), do: do_execute(saga) |> next()

  def compensate(%Sagax{stack: []} = saga), do: saga
  def compensate(%Sagax{} = saga), do: do_compensate(saga) |> next()

  def next(%Sagax{state: :ok} = saga), do: execute(saga)
  def next(%Sagax{state: :error} = saga), do: compensate(saga)

  defp do_execute(%Sagax{queue: [{_, %Sagax{} = inner_saga, _, _} | _]} = saga) do
    %{inner_saga | results: saga.results}
    |> Sagax.inherit(saga)
    |> execute()
    |> handle_execute_result(saga)
  end

  defp do_execute(%Sagax{queue: [effects | tail]} = saga) when is_list(effects) do
    inner_saga =
      effects
      |> Task.async_stream(
        fn effect -> do_execute(%{saga | queue: [effect]}) end,
        saga.opts
      )
      |> Enum.reduce_while(%{saga | results: %{}}, fn
        {:ok, %{state: :error} = result_saga}, acc ->
          {:halt,
           %{
             acc
             | state: :error,
               stack: acc.stack ++ result_saga.stack,
               results: Map.merge(acc.results, result_saga.results),
               last_result: result_saga.last_result
           }}

        {:ok, result_saga}, acc ->
          {:cont,
           %{
             acc
             | stack: acc.stack ++ result_saga.stack,
               results: Map.merge(acc.results, result_saga.results)
           }}
      end)

    %{
      saga
      | state: inner_saga.state,
        queue: tail,
        stack: [inner_saga.stack | saga.stack],
        results: Map.merge(saga.results, inner_saga.results),
        last_result: inner_saga.last_result || saga.last_result
    }
  end

  defp do_execute(%Sagax{queue: [{_, effect, _, opts} | _]} = saga) do
    effect
    |> safe_apply([saga.results, saga.args, saga.context], opts, saga.opts)
    |> handle_execute_result(saga)
  end

  def do_compensate(%Sagax{stack: [items | tail]} = saga) when is_list(items) do
    inner_saga =
      items
      |> Task.async_stream(
        fn item -> {elem(item, 0), do_compensate(%{saga | stack: [item]})} end,
        saga.opts
      )
      |> Enum.reduce(saga, fn {:ok, {id, _}}, acc ->
        %{acc | results: Map.delete(acc.results, id)}
      end)

    %{inner_saga | stack: tail}
  end

  def do_compensate(%Sagax{stack: [{_, %Sagax{} = inner_saga, _, _} | _]} = saga) do
    %{saga | stack: inner_saga.stack}
    |> compensate()
    |> handle_compensate_result(saga)
  end

  def do_compensate(%Sagax{stack: [{_, _, :noop, _} | _]} = saga),
    do: handle_compensate_result(:ok, saga)

  def do_compensate(%Sagax{stack: [{id, _, comp, opts} | _], results: results} = saga) do
    result = Map.get(results, id)

    comp
    |> safe_apply([result, results, saga.args, saga.context], opts, saga.opts)
    |> handle_compensate_result(saga)
  end

  defp handle_execute_result(:ok, %{queue: [item | queue]} = saga),
    do: %{
      saga
      | queue: queue,
        stack: [item | saga.stack],
        results: Map.put(saga.results, elem(item, 0), nil)
    }

  defp handle_execute_result({:ok, value}, %{queue: [item | queue]} = saga),
    do: %{
      saga
      | queue: queue,
        stack: [item | saga.stack],
        results: Map.put(saga.results, elem(item, 0), value)
    }

  defp handle_execute_result({:ok, value, tag}, %{queue: [item | queue]} = saga)
       when is_binary(tag) or is_atom(tag) or is_tuple(tag),
       do: %{
         saga
         | queue: queue,
           stack: [item | saga.stack],
           results: Map.put(saga.results, elem(item, 0), {value, tag})
       }

  defp handle_execute_result(
         %Sagax{state: :ok, last_result: last_result, results: results} = inner_saga,
         %{queue: [item | queue]} = saga
       ),
       do: %{
         saga
         | queue: queue,
           stack: [put_elem(item, 1, inner_saga) | saga.stack],
           results: Map.merge(saga.results, results),
           last_result: last_result
       }

  defp handle_execute_result(
         %Sagax{state: :error, last_result: last_result, results: results},
         %{queue: [item | _]} = saga
       ),
       do: %{
         saga
         | stack: [item | saga.stack],
           results: Map.merge(saga.results, results),
           last_result: last_result
       }

  defp handle_execute_result({:error, error_or_result}, %{queue: [item | queue]} = saga),
    do: %{
      saga
      | state: :error,
        queue: queue,
        stack: [item | saga.stack],
        results: Map.put(saga.results, elem(item, 0), error_or_result),
        last_result: error_or_result
    }

  defp handle_execute_result({:raise, {_, _} = exception}, %{queue: [item | queue]} = saga),
    do: %{
      saga
      | state: :error,
        queue: queue,
        stack: [item | saga.stack],
        results: Map.put(saga.results, elem(item, 0), {exception, nil}),
        last_result: exception
    }

  defp handle_execute_result(_result, _saga) do
    # TODO: Implement this
    raise "Invalid result"
  end

  defp handle_compensate_result(result, %{stack: [item | stack], results: results} = saga) do
    case result do
      :ok ->
        %{saga | stack: stack, results: Map.delete(results, elem(item, 0))}

      {:error, _error_or_result} ->
        # TODO: Implement an on_error handler
        raise "Panic"

      {:raise, {exception, stacktrace}} ->
        # TODO: Implement an on_error handler
        reraise(exception, stacktrace)

      # {:exit, :timeout} ->
      #   compensate(%{
      #     saga
      #     | aborted?: true,
      #       stack: [item | saga.stack],
      #       results: [{nil, nil} | saga.results]
      #       last_result: nil
      #   })

      %Sagax{results: results} ->
        %{saga | stack: stack, results: results}
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
