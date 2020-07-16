defmodule Sagax.Executor do
  @moduledoc false
  alias Sagax.Utils

  @spec execute(Sagax.t()) :: Sagax.t()
  def execute(%Sagax{queue: []} = saga), do: saga
  def execute(%Sagax{} = saga), do: do_execute(saga) |> next()

  @spec compensate(Sagax.t()) :: Sagax.t()
  def compensate(%Sagax{stack: []} = saga), do: saga
  def compensate(%Sagax{} = saga), do: do_compensate(saga) |> next()

  def next(%Sagax{state: :ok} = saga), do: execute(saga)
  def next(%Sagax{state: :error} = saga), do: compensate(saga)

  defp execute_lazy(saga, lazy_func) do
    lazy_func
    |> safe_apply([saga, saga.args, saga.context], saga.opts, saga.opts)
    |> case do
      %Sagax{} = result ->
        {:ok, result}

      {:ok, %Sagax{}} = result ->
        result

      {:error, _} = error ->
        error

      {:raise, {exception, stacktrace}} ->
        # TODO: Implement an on_error handler
        reraise(exception, stacktrace)

      result ->
        raise RuntimeError,
              "Unexpected result from function, expected a %Sagax{} struct but got " <>
                inspect(result, limit: 2, printable_limit: 10)
    end
  end

  defp do_execute(%Sagax{queue: [{_, %Sagax{} = inner_saga, _, _} | _]} = saga) do
    %{inner_saga | results: saga.results}
    |> Sagax.inherit(saga)
    |> execute()
    |> handle_execute_result(saga)
  end

  defp do_execute(%Sagax{queue: [{id, effects} | _]} = saga) when is_list(effects) do
    effects
    |> Enum.reduce_while(saga, fn
      {id, func}, acc ->
        case execute_lazy(Utils.delete(acc, id), func) do
          {:ok, new_saga} -> {:cont, new_saga}
          {:error, error} -> {:halt, {acc, error}}
        end

      _, acc ->
        {:cont, acc}
    end)
    |> case do
      %Sagax{} = saga ->
        # A lazy function can prepend new stages, so we need to check if the first
        # item in the queue is still the same as `effects`. If this is the case,
        # we can continue executing. If not, we use `next` to process the new items first.
        if Utils.peek_id(saga.queue) !== id do
          next(saga)
        else
          inner_saga =
            saga.queue
            |> Utils.peek_effect()
            |> Task.async_stream(
              fn effect -> do_execute(%{saga | queue: [effect], stack: []}) end,
              saga.opts
            )
            |> Enum.reduce_while(%{saga | results: %{}}, fn
              {:ok, %{state: :ok} = result_saga}, acc ->
                {:cont,
                 %{
                   acc
                   | stack: acc.stack ++ result_saga.stack,
                     results: Map.merge(acc.results, result_saga.results)
                 }}

              {:ok, %{state: :error} = result_saga}, acc ->
                {:halt,
                 %{
                   acc
                   | state: :error,
                     stack: acc.stack ++ result_saga.stack,
                     results: Map.merge(acc.results, result_saga.results),
                     last_result: result_saga.last_result
                 }}
            end)

          %{
            saga
            | state: inner_saga.state,
              queue: Utils.delete(saga.queue, id),
              stack: [{id, inner_saga.stack} | saga.stack],
              results: Map.merge(saga.results, inner_saga.results),
              last_result: inner_saga.last_result || saga.last_result
          }
        end

      {saga, error} ->
        %{
          saga
          | state: :error,
            queue: Utils.delete(saga.queue, id),
            last_result: error
        }
    end
  end

  defp do_execute(%Sagax{queue: [{_, func} | tail]} = saga) do
    case execute_lazy(%{saga | queue: tail}, func) do
      {:ok, result_saga} ->
        result_saga

      {:error, error} ->
        %{saga | state: :error, queue: tail, last_result: error}
    end
  end

  defp do_execute(%Sagax{queue: [{_, effect, _, opts} | _]} = saga) do
    effect
    |> safe_apply([Map.values(saga.results), saga.args, saga.context], opts, saga.opts)
    |> handle_execute_result(saga)
  end

  def do_compensate(%Sagax{stack: [{_, items} | tail]} = saga) when is_list(items) do
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
    %{inner_saga | state: :error}
    |> compensate()
    |> handle_compensate_result(saga)
  end

  def do_compensate(%Sagax{stack: [{_, _, :noop, _} | _]} = saga),
    do: handle_compensate_result(:ok, saga)

  def do_compensate(%Sagax{stack: [{id, _, comp, opts} | _], results: results} = saga) do
    result = Map.get(results, id)

    comp
    |> safe_apply([result, Map.values(results), saga.args, saga.context], opts, saga.opts)
    |> handle_compensate_result(saga)
  end

  defp handle_execute_result(:ok, %{queue: [item | queue]} = saga),
    do: %{saga | queue: queue, stack: [item | saga.stack]}

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
         | state: :error,
           stack: [item | saga.stack],
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

  # TODO: Implement an on_error handler
  defp handle_execute_result({:raise, {exception, stacktrace}}, _),
    do: reraise(exception, stacktrace)

  # TODO: Implement this
  defp handle_execute_result(_result, _saga), do: raise("Panic")

  defp handle_compensate_result(:ok, %{stack: [item | stack], results: results} = saga),
    do: %{saga | stack: stack, results: Map.delete(results, elem(item, 0))}

  # TODO: Implement an on_error handler
  defp handle_compensate_result({:error, _error_or_result}, _), do: raise("Panic")

  # TODO: Implement an on_error handler
  defp handle_compensate_result({:raise, {exception, stacktrace}}, _),
    do: reraise(exception, stacktrace)

  defp handle_compensate_result(%Sagax{results: results}, %{stack: [_ | stack]} = saga),
    do: %{saga | stack: stack, results: results}

  # TODO: Implement this
  defp handle_compensate_result(_, _), do: raise("Panic")

  defp safe_apply(func, args, opts, saga_opts) do
    task =
      fn ->
        try do
          apply(func, args ++ [Keyword.merge(saga_opts, opts)])
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
