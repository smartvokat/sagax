defmodule Sagax do
  @moduledoc """
  A saga.
  """

  alias Sagax.Executor

  defstruct args: nil,
            context: nil,
            executed?: false,
            last_result: nil,
            opts: [],
            queue: [],
            results: %{},
            stack: [],
            state: :ok

  defguard is_tag(tag) when is_atom(tag) or is_binary(tag)

  @doc """
  Creates a new saga.
  """
  def new(opts \\ []) do
    args = Keyword.get(opts, :args, nil)
    context = Keyword.get(opts, :context, nil)

    opts = Keyword.drop(opts, [:args, :context])
    opts = Keyword.merge([max_concurrency: System.schedulers_online()], opts)

    %Sagax{opts: opts, args: args, context: context}
  end

  def put_args(%Sagax{} = saga, args), do: %{saga | args: args}

  def put_new_args(%Sagax{} = saga, args),
    do: if(is_nil(saga.args), do: %{saga | args: args}, else: saga)

  def put_context(%Sagax{} = saga, context), do: %{saga | context: context}

  def put_new_context(%Sagax{} = saga, context),
    do: if(is_nil(saga.context), do: %{saga | context: context}, else: saga)

  def inherit(%Sagax{} = base, %Sagax{} = saga) do
    base
    |> Map.update(:args, saga.args, fn v -> if is_nil(v), do: saga.args, else: v end)
    |> Map.update(:context, saga.context, fn v -> if is_nil(v), do: saga.context, else: v end)
  end

  @doc """
  Adds a function which receives the saga for lazy manipulation.
  """
  def add_lazy(saga, func) when is_function(func, 4),
    do: %{saga | queue: saga.queue ++ [{unique_id(), func}]}

  def add_lazy_async(%Sagax{} = saga, func) when is_function(func, 4),
    do: do_add_async(saga, {unique_id(), func})

  @doc """
  Adds an effect and compensation to the saga.
  """
  def add(saga, effect, compensation \\ :noop, opts \\ [])

  def add(_, effect, _, _) when not is_function(effect, 4) and not is_struct(effect),
    do:
      raise(
        ArgumentError,
        "Invalid effect function. Either a function with arity 4 " <>
          "or another %Sagax{} struct is allowed."
      )

  def add(_, _, compensation, _) when not is_function(compensation, 5) and compensation !== :noop,
    do:
      raise(
        ArgumentError,
        "Invalid compensation function. Either a function with arity 5 or :noop is allowed."
      )

  def add(%Sagax{queue: queue} = saga, effect, compensation, opts),
    do: %{saga | queue: queue ++ [{unique_id(), effect, compensation, opts}]}

  def add_async(_, _, compensation \\ :noop, opts \\ [])

  def add_async(_, effect, _, _) when not is_function(effect, 4) and not is_struct(effect),
    do:
      raise(
        ArgumentError,
        "Invalid effect function. Either a function with arity 4 " <>
          "or another %Sagax{} struct is allowed."
      )

  def add_async(_, _, compensation, _)
      when not is_function(compensation, 5) and compensation !== :noop,
      do:
        raise(
          ArgumentError,
          "Invalid compensation function. Either a function with arity 5 or :noop is allowed."
        )

  def add_async(%Sagax{} = saga, effect, compensation, opts),
    do: do_add_async(saga, {unique_id(), effect, compensation, opts})

  @doc """
  Executes the function defined in the saga.
  """
  def execute(%Sagax{} = saga, args \\ nil, context \\ nil) do
    saga = if !is_nil(args), do: %{saga | args: args}, else: saga
    saga = if !is_nil(context), do: %{saga | context: context}, else: saga

    saga
    |> Executor.execute()
    |> case do
      %Sagax{state: :ok} = saga ->
        {:ok, %{saga | executed?: true, results: all(saga)}}

      %Sagax{state: :error, last_result: {error, stacktrace}} ->
        reraise(error, stacktrace)

      %Sagax{state: :error, last_result: result} = saga ->
        {:error, result, %{saga | executed?: true}}
    end
  end

  def find(results, query, default \\ nil)

  def find(%Sagax{results: results}, query, default) when is_map(results),
    do: find(Map.values(results), query, default)

  def find(%Sagax{results: results}, query, default) when is_list(results),
    do: find(results, query, default)

  def find(results, query, default)
      when (is_list(results) and is_tuple(query)) or is_binary(query) or is_atom(query) do
    match = Enum.find(results, &matches?(&1, query))
    if is_tuple(match), do: elem(match, 0), else: default
  end

  def find(_, _, default), do: default

  def all(%Sagax{results: results, executed?: true}), do: results
  def all(%Sagax{results: results, executed?: false}), do: Map.values(results)

  def all(%Sagax{results: results}, query)
      when is_tuple(query) or is_binary(query) or is_atom(query) do
    results
    |> Enum.filter(&matches?(&1, query))
    |> Enum.map(&elem(&1, 0))
  end

  def transaction(%Sagax{} = saga, repo, transaction_opts \\ []) do
    return =
      repo.transaction(
        fn ->
          case execute(saga) do
            {:ok, saga} ->
              {:ok, saga}
            {:error, result, _saga} ->
              repo.rollback(result)
          end
        end,
        transaction_opts
      )

    case return do
      {:ok, {:error, reason}} ->
        {:error, reason, %{saga | executed?: true, state: :error, last_result: reason, queue: []}}
      {:ok, result} ->
        result
      {:error, reason} ->
        {:error, reason, %{saga | executed?: true, state: :error, last_result: reason, queue: []}}
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

  defp do_add_async(%Sagax{queue: queue} = saga, op) do
    prev_stage = List.last(queue)

    if is_tuple(prev_stage) && is_list(elem(prev_stage, 1)) do
      queue =
        List.update_at(queue, length(queue) - 1, fn {_, items} = item ->
          put_elem(item, 1, items ++ [op])
        end)

      %{saga | queue: queue}
    else
      %{saga | queue: queue ++ [{unique_id(), [op]}]}
    end
  end
end
