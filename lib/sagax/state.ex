defmodule Sagax.State do
  defstruct aborted?: false,
            stages: [],
            compensations: [],
            results: [],
            last_result: nil,
            args: nil,
            context: nil

  def get_results(state), do: Enum.reverse(state.results)
end
