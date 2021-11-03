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
  @spec new(keyword()) :: Sagax.t()
  def new(fields \\ []),
    do:
      struct!(
        Sagax,
        Keyword.merge([id: Utils.new_id()], fields)
      )

  @doc """
  Calls Executer to execute the given Saga.
  """
  @spec execute(Sagax.t()) :: {:ok, any()} | {:error, [Sagax.Next.Error.t()]}
  def execute(%Sagax{} = saga) do
    Sagax.Executer.execute(saga)
  end

  @doc """
  Puts the result of `effect` under `key` in the result of the saga.
  """
  @spec put(Sagax.t(), atom(), Sagax.Op.effect(), Sagax.Op.compensation()) :: Sagax.t()
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
  Adds an effect to run as part of the saga without storing its result.
  """
  @spec run(Sagax.t(), Sagax.Op.effect(), Sagax.Op.compensation()) :: Sagax.t()
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
end
