defmodule Sagax do
  @moduledoc """
  A saga.
  """
  alias __MODULE__

  @type effect :: any()
  @type compensation :: any()

  @typep callback :: (map() -> Sagax.t())
  @typep transaction :: any()

  @typep op :: {atom(), keyword(), effect(), compensation()}

  @type t() :: %__MODULE__{
          args: map() | nil,
          callbacks: list(callback),
          context: map() | nil,
          errors: list(any()),
          executed?: boolean(),
          queue: list(op),
          stack: list(op),
          state: :ok | :error,
          tx: transaction,
          value: map() | list() | nil
        }

  defstruct value: nil,
            args: nil,
            context: nil,
            queue: [],
            stack: [],
            state: :ok,
            executed?: false,
            callbacks: [],
            tx: nil,
            errors: []

  @spec new(keyword()) :: Sagax.t()
  def new(fields \\ []), do: struct!(Sagax, fields)

  @doc """
  Puts the result of `effect` under `key` in the final result of the saga.
  """
  @spec put(Sagax.t(), atom(), any(), any()) :: Sagax.t()
  def put(saga, key, effect, comp \\ :noop),
    do: %{saga | queue: [{:put, [key: key], effect, comp} | saga.queue]}

  @doc """
  Adds an effect to run as part of the saga.
  """
  @spec run(Sagax.t(), any(), any()) :: Sagax.t()
  def run(saga, effect, comp \\ :noop),
    do: %{saga | queue: [{:run, [], effect, comp} | saga.queue]}

  @doc """
  Adds a callback to run after the saga was executed successfully. All callbacks
  are run outside of transactions.
  """
  @spec then(Sagax.t(), callback) :: Sagax.t()
  def then(saga, callback), do: %{saga | queue: [callback | saga.callbacks]}
end
