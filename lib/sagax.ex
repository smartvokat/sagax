defmodule Sagax do
  @moduledoc false

  alias __MODULE__
  alias Sagax.State

  defstruct stages: [], results: []

  @doc """
  Creates a new saga.
  """
  def new(), do: %Sagax{}

  # def get(%Sagax{} = saga, query), do: nil
  # def all(%Sagax{} = saga, query), do: []

  @doc """
  Adds a function to the saga.
  """
  def run(%Sagax{stages: stages} = saga, effect, compensation \\ :noop),
    do: %{saga | stages: [{effect, compensation} | stages]}

  def run_async(_, _, compensation \\ :noop)

  def run_async(%Sagax{stages: [last_effect | stages]} = saga, effect, compensation)
      when is_list(last_effect),
      do: %{saga | stages: [[{effect, compensation} | last_effect] | stages]}

  def run_async(%Sagax{stages: stages} = saga, effect, compensation),
    do: %{saga | stages: [[{effect, compensation}] | stages]}

  @doc """
  Executes the function defined in the saga.
  """
  def execute(%Sagax{} = saga, args, context \\ nil) do
    case Sagax.Executor.execute(saga, args, context) do
      %State{aborted?: false} = state ->
        {:ok, State.get_results(state)}

      %State{aborted?: true, last_result: {error, _stacktrace}} ->
        {:error, error}

      %State{aborted?: true, last_result: result} ->
        {:error, result}
    end
  end
end
