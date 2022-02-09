defmodule Sagax.Next do
  @moduledoc """
  A saga.
  """
  alias Sagax.Next, as: Sagax
  alias Sagax.{Op, Utils}

  require Sagax.Op

  @typep transaction :: any()

  @type t() :: %__MODULE__{
          args: map() | nil,
          callbacks: list(Sagax.Op.callback()),
          context: map() | nil,
          errors: list(any()),
          id: integer(),
          ops: list(Sagax.Op.t()),
          state: :new | :ok | :error,
          tx: transaction(),
          value: map() | list() | nil,
          opts: Keyword.t() | []
        }

  defstruct args: nil,
            callbacks: [],
            context: nil,
            errors: [],
            id: nil,
            ops: [],
            state: :new,
            tx: nil,
            value: nil,
            opts: []

  @doc """
  Creates a new saga.
  """
  @spec new(keyword()) :: Sagax.Next.t()
  def new(fields \\ []) do
    struct!(
      Sagax,
      Keyword.merge([id: Utils.new_id()], fields)
    )
  end

  @doc """
  Calls the executer to execute the given saga.
  """
  @spec execute(Sagax.Next.t()) :: Sagax.Next.t()
  def execute(%Sagax{} = saga), do: Sagax.Executer.execute(saga)

  @doc """
  Puts the result of `effect` under `key` in the result of the saga.
  """
  @spec put(Sagax.Next.t(), atom(), Sagax.Next.Op.effect(), Sagax.Next.Op.compensation()) ::
          Sagax.Next.t()
  def put(_saga, _key, _effect, comp \\ :noop)

  def put(%Sagax{} = saga, key, %Sagax{} = nested_saga, comp) do
    op = Op.new_put_op(saga.id, key, nested_saga, comp)
    %{saga | ops: [op | saga.ops]}
  end

  def put(%Sagax{} = saga, key, effect, comp) do
    op = Op.new_put_op(saga.id, key, effect, comp)
    %{saga | ops: [op | saga.ops]}
  end

  @doc """
  Same as `put/4` but only if `condition` evaluates to `true`.

  ## Examples

    iex> args = %{foo: :bar}
    iex> Sagax.new()
    ...> |> Sagax.put_if(Map.has_key?(args, :foo), :baz, fn -> {:ok, :xyz} end)
    ...> |> Sagax.execute()

  """
  @spec put_if(
          Sagax.Next.t(),
          boolean() | (() -> boolean()),
          atom(),
          Sagax.Next.Op.effect(),
          Sagax.Next.Op.compensation()
        ) :: Sagax.Next.t()
  def put_if(_saga, _condition, _key, _effect, comp \\ :noop)

  def put_if(%Sagax{} = saga, condition, key, effect, comp),
    do: maybe_compose(condition, :put, [saga, key, effect, comp])

  @doc """
  Adds an effect to run as part of the saga without storing its result.
  """
  @spec run(Sagax.Next.t(), Sagax.Next.Op.effect(), Sagax.Next.Op.compensation()) ::
          Sagax.Next.t()
  def run(%Sagax{} = saga, effect, comp \\ :noop) do
    op = Op.new_run_op(saga.id, effect, comp)
    %{saga | ops: [op | saga.ops]}
  end

  def transaction(%Sagax{} = saga, repo, transaction_opts \\ []) do
    opts =
      Keyword.merge(
        saga.opts,
        repo: repo,
        execute_in_transaction: true,
        transaction_opts: transaction_opts
      )

    %{saga | opts: opts}
  end

  defp maybe_compose(condition, func, args) do
    should_compose =
      cond do
        is_boolean(condition) ->
          condition

        is_function(condition) ->
          result = condition.()

          if is_boolean(result) do
            result
          else
            raise ArgumentError, "Expected condition to return a boolean value"
          end

        true ->
          raise ArgumentError, "Expected condition to be a boolean or function"
      end

    if should_compose do
      apply(__MODULE__, func, args)
    else
      List.first(args)
    end
  end
end
