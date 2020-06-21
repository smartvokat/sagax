defmodule Sagax do
  @moduledoc false

  alias __MODULE__
  alias Sagax.Executor
  alias Sagax.State

  defguard is_tag(tag) when is_atom(tag) or is_binary(tag)

  defstruct executed?: false, results: [], queue: [], opts: []

  @doc """
  Creates a new saga.
  """
  def new(opts \\ []) do
    opts = Keyword.merge([max_concurrency: System.schedulers_online()], opts)
    %Sagax{opts: opts}
  end

  def find(%Sagax{results: results}, query)
      when is_tuple(query) or is_binary(query) or is_atom(query) do
    match = Enum.find(results, &matches?(&1, query))
    if is_tuple(match), do: elem(match, 0), else: nil
  end

  def find(_, _), do: nil

  def all(%Sagax{results: results}, query)
      when is_tuple(query) or is_binary(query) or is_atom(query) do
    results
    |> Enum.filter(&matches?(&1, query))
    |> Enum.map(&elem(&1, 0))
  end

  @doc """
  Adds a function to the saga.
  """
  def run(saga, effect, compensation \\ :noop, opts \\ [])

  def run(_, effect, _, _) when not is_function(effect, 4) and not is_struct(effect),
    do: raise(ArgumentError, "Invalid effect function")

  def run(_, _, compensation, _) when not is_function(compensation, 5) and compensation !== :noop,
    do: raise(ArgumentError, "Invalid compensation function")

  def run(%Sagax{queue: queue} = saga, effect, compensation, opts),
    do: %{saga | queue: [{unique_id(), effect, compensation, opts} | queue]}

  def run_async(_, _, compensation \\ :noop, opts \\ [])

  def run_async(%Sagax{queue: [head | queue]} = saga, effect, compensation, opts)
      when is_list(head),
      do: %{saga | queue: [[{unique_id(), effect, compensation, opts} | head] | queue]}

  def run_async(%Sagax{queue: queue} = saga, effect, compensation, opts),
    do: %{saga | queue: [[{unique_id(), effect, compensation, opts}] | queue]}

  @doc """
  Executes the function defined in the saga.
  """
  def execute(%Sagax{} = saga, args, context \\ nil) do
    saga
    |> State.from_saga(args, context)
    |> Executor.execute()
    |> case do
      %State{aborted?: false} = state ->
        {:ok, %{saga | executed?: true, results: Map.values(state.results)}}

      %State{aborted?: true, last_result: {error, _stacktrace}} ->
        # reraise(error, stacktrace)
        {:error, error}

      %State{aborted?: true, last_result: result} ->
        {:error, result}
    end
  end

  defp unique_id(), do: System.unique_integer([:positive])

  defp matches?({_, {_, _}}, {:_, :_}), do: true
  defp matches?({_, {ns_left, _}}, {ns_right, :_}), do: ns_left == ns_right
  defp matches?({_, {_, tag_left}}, {:_, tag_right}), do: tag_left == tag_right

  defp matches?({_, {ns_left, tag_left}}, {ns_right, tag_right}),
    do: ns_left == ns_right && tag_left == tag_right

  defp matches?({_, {_, tag_left}}, tag_right) when is_tag(tag_right), do: tag_left == tag_right
  defp matches?({_, tag_left}, tag_right) when is_tag(tag_right), do: tag_left == tag_right
  defp matches?(_, _), do: false
end
