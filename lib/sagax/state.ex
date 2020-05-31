defmodule Sagax.State do
  alias __MODULE__

  defstruct aborted?: false,
            queue: [],
            stack: [],
            results: %{},
            last_result: nil,
            args: nil,
            context: nil,
            opts: []

  def from_saga(%Sagax{} = saga, args \\ %{}, context \\ nil) do
    queue =
      saga.queue
      |> Enum.reverse()
      |> Enum.map(fn
        stage when is_list(stage) and length(stage) === 1 -> List.first(stage)
        stages when is_list(stages) -> Enum.reverse(stages)
        stage -> stage
      end)

    %State{queue: queue, args: args, context: context, opts: saga.opts}
  end
end
