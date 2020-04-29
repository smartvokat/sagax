defmodule Sagax.Executor do
  alias __MODULE__
  alias Sagax
  alias Sagax.State

  def execute(%Sagax{} = saga, args, context \\ nil) do
    stages =
      saga.stages
      |> Enum.reverse()
      |> Enum.map(fn
        stage when is_list(stage) and length(stage) === 1 -> List.first(stage)
        stages when is_list(stages) -> Enum.reverse(stages)
        stage -> stage
      end)

    next_stage(%State{stages: stages, args: args, context: context})
  end

  defp next_stage(%{stages: stages} = state) when stages == [], do: state

  defp next_stage(%{stages: [{%Sagax{} = saga, compensation} | tail], results: results} = state) do
    case Executor.execute(saga, state.args, state.context) do
      %State{aborted?: false} = nested_state ->
        next_stage(%{
          state
          | stages: tail,
            compensations: [nested_state, compensation] ++ state.compensations,
            results: [nested_state.results | results]
        })

      %State{aborted?: true} = nested_state ->
        next_compensation(%{
          state
          | aborted?: true,
            compensations: [nested_state, compensation] ++ state.compensations,
            results: [nested_state.results | results],
            last_result: nested_state.last_result
        })
    end
  end

  defp next_stage(%{stages: [{effect, compensation} | tail], results: results} = state) do
    case apply_effect(effect, [results, state.args, state.context]) do
      {:ok, result} ->
        next_stage(%{
          state
          | stages: tail,
            compensations: [compensation | state.compensations],
            results: [result | results]
        })

      {:ok, tag, result} ->
        next_stage(%{
          state
          | stages: tail,
            compensations: [compensation | state.compensations],
            results: [{tag, result} | results]
        })

      {:raise, exception} ->
        next_compensation(%{
          state
          | aborted?: true,
            compensations: [compensation | state.compensations],
            results: [exception | results],
            last_result: exception
        })

      {:error, error_or_result} ->
        next_compensation(%{
          state
          | aborted?: true,
            compensations: [compensation | state.compensations],
            results: [error_or_result | results],
            last_result: error_or_result
        })
    end
  end

  defp apply_effect(fun, args, timeout \\ 5000) do
    fn ->
      Process.flag(:trap_exit, true)

      try do
        apply(fun, args)
      rescue
        exception ->
          {:raise, {exception, __STACKTRACE__}}
      end
    end
    |> Task.async()
    |> Task.await(timeout)
  end

  defp next_compensation(%{compensations: compensations} = state) when compensations == [],
    do: state

  defp next_compensation(
         %{compensations: [:noop | compensations], results: [_ | results]} = state
       ),
       do: next_compensation(%{state | compensations: compensations, results: results})

  defp next_compensation(
         %{compensations: [compensation | compensations], results: [result | results]} = state
       ) do
    case apply(compensation, [result, results, state.args, state.context]) do
      :ok -> next_compensation(%{state | compensations: compensations, results: results})
    end
  end
end
