defmodule Sagax.TaskExecuter do
  alias Sagax
  alias Sagax.Op

  import Sagax.Executer

  @behaviour Sagax.Executer

  @doc """
  Executes a saga.
  """
  @impl true
  def execute(saga), do: do_execute(%{saga | queue: Enum.reverse(saga.queue)})

  defp do_execute(%Sagax{queue: [], callbacks: []} = saga), do: %{saga | executed?: true}

  defp do_execute(%Sagax{queue: [%Sagax{} = nested_saga | _]} = saga) do
    case execute(nested_saga) do
      %Sagax{state: :ok} = result_saga ->
        handle_effect_result({:ok, result_saga.value}, saga)

      %Sagax{state: :error} = result_saga ->
        raise "foo"

        do_compensate(%{
          saga
          | state: :error,
            errors: result_saga.errors,
            stack: [nested_saga | saga.stack]
        })
    end
  end

  defp do_execute(%Sagax{queue: [op | _]} = saga) when is_op(op),
    do: apply_effect(saga, op) |> handle_effect_result(saga)

  # The effect returned `:error` without further information. This
  # is not very helpful, but we'll handle it
  defp handle_effect_result(:error, %Sagax{queue: [op | _]} = saga),
    do: do_compensate(%{saga | stack: [op | saga.stack]})

  defp handle_effect_result(%Sagax{} = nested_saga, %Sagax{queue: [_op | _]} = saga),
    do: do_execute(%{saga | queue: [nested_saga | saga.queue]})

  defp handle_effect_result(result, %Sagax{queue: [op | ops]} = saga) do
    case Op.apply(saga, op, result) do
      %Sagax{} = saga ->
        do_execute(%{saga | queue: ops, stack: [op | saga.stack]})

      error ->
        do_compensate(%{
          saga
          | state: :error,
            errors: [error | saga.errors],
            stack: [op | saga.stack]
        })
    end
  end

  defp apply_effect(saga, {_, _, effect, _} = op) do
    cond do
      is_function(effect, 0) ->
        apply(effect, [])

      is_function(effect, 1) ->
        apply(effect, [saga.value])

      is_function(effect, 2) ->
        apply(effect, [saga.value, saga.args])

      is_function(effect, 3) ->
        apply(effect, [saga.value, saga.args, saga.context])

      true ->
        raise ArgumentError,
              "Expected a function with arity 0, 1, 2 or 3 as the effect " <>
                "in operation #{inspect(op)}"
    end
  end

  # At this point we have compensated all effects in the saga and can yield to the caller
  defp do_compensate(%Sagax{stack: []} = saga), do: saga

  # A `:noop` compensation does not do anything
  defp do_compensate(%Sagax{stack: [{_, _, _, :noop} | _]} = saga),
    do: handle_compensation_result(:ok, saga)

  defp handle_compensation_result(:ok, %Sagax{stack: [_ | ops]} = saga),
    do: do_compensate(%{saga | stack: ops})

  # The compensation returned an unexpected value. We'll create an expection,
  # but don't raise it to let the rollback continue
  defp handle_compensation_result(_, %Sagax{stack: [op | ops]} = saga) do
    message = "Unexpected result of compensation in operation #{inspect(op)}"
    exception = %RuntimeError{message: message}

    do_compensate(%{saga | errors: [exception | saga.errors], stack: ops})
  end

  # defp apply_compensation(saga, {_, _, _, comp} = op, value) do
  #   cond do
  #     is_function(comp, 1) ->
  #       apply(comp, [value])

  #     is_function(comp, 2) ->
  #       apply(comp, [value, saga.args])

  #     is_function(comp, 3) ->
  #       apply(comp, [value, saga.args, saga.context])

  #     true ->
  #       raise ArgumentError,
  #             "Expected a function with arity 1, 2 or 3 as the compensation " <>
  #               "in operation #{inspect(op)}"
  #   end
  # end
end
