defmodule Sagax do
  @moduledoc """
  A saga.
  """
  alias __MODULE__

  @typep callback :: (map() -> Sagax.t())
  @typep transaction :: any()

  @type t() :: %__MODULE__{
          args: map() | nil,
          callbacks: list(Sagax.Op.callback()),
          context: map() | nil,
          errors: list(any()),
          executed?: boolean(),
          queue: list(Sagax.Op.t()),
          stack: list(Sagax.Op.t()),
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

  defdelegate put(saga, key, effect, comp \\ :noop), to: Sagax.Op
  defdelegate run(saga, effect, comp \\ :noop), to: Sagax.Op

  @spec new(keyword()) :: Sagax.t()
  def new(fields \\ []), do: struct!(Sagax, fields)

  @doc """
  Adds a callback to run after the saga was executed successfully. All callbacks
  are run outside of transactions.
  """
  @spec then(Sagax.t(), callback) :: Sagax.t()
  def then(saga, callback), do: %{saga | queue: [callback | saga.callbacks]}
end
