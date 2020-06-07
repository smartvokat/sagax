defmodule Sagax do
  @moduledoc false

  alias __MODULE__
  alias Sagax.State
  alias Sagax.Result

  defstruct queue: [], results: [], opts: []

  @doc """
  Creates a new saga.
  """
  def new(opts \\ []),
    do: %Sagax{
      opts:
        Keyword.merge(opts,
          max_concurrency: System.schedulers_online()
        )
    }

  def get(%Result{results: results}, {_namespace, _value} = tag) do
    match =
      Enum.find(results, fn result ->
        is_tuple(result) && elem(result, 1) == tag
      end)

    if is_nil(match), do: match, else: elem(match, 0)
  end

  # def all(%Sagax{} = saga, query), do: []

  @doc """
  Adds a function to the saga.
  """
  def run(saga, effect, compensation \\ :noop, opts \\ [])

  def run(_, effect, _, _) when not is_function(effect, 4) and not is_struct(effect),
    do: raise(ArgumentError, "Invalid effect function")

  def run(_, _, compensation, _) when not is_function(compensation, 5) and compensation !== :noop,
    do: raise(ArgumentError, "Invalid compensation function")

  def run(%Sagax{queue: queue} = saga, effect, compensation, opts),
    do: %{saga | queue: [{effect, compensation, opts} | queue]}

  def run_async(_, _, compensation \\ :noop, opts \\ [])

  def run_async(%Sagax{queue: [head | queue]} = saga, effect, compensation, opts)
      when is_list(head),
      do: %{saga | queue: [[{effect, compensation, opts} | head] | queue]}

  def run_async(%Sagax{queue: queue} = saga, effect, compensation, opts),
    do: %{saga | queue: [[{effect, compensation, opts}] | queue]}

  @doc """
  Executes the function defined in the saga.
  """
  def execute(%Sagax{} = saga, args, context \\ nil) do
    saga
    |> State.from_saga(args, context)
    |> Sagax.Executor.execute()
    |> case do
      %State{aborted?: false} = state ->
        {:ok, %Result{results: Map.values(state.results)}}

      %State{aborted?: true, last_result: {error, stacktrace}} ->
        reraise(error, stacktrace)

      %State{aborted?: true, last_result: result} ->
        {:error, result}
    end
  end
end
