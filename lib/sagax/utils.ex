defmodule Sagax.Utils do
  @moduledoc false

  def delete(%Sagax{} = saga, id), do: do_delete(saga, id)

  def do_delete(%Sagax{queue: queue} = saga, id), do: %{saga | queue: do_delete(queue, id)}

  def do_delete(stages, id) when is_list(stages),
    do:
      Enum.reduce(stages, [], fn stage, acc ->
        result = do_delete(stage, id)
        if is_nil(result), do: acc, else: acc ++ [result]
      end)

  def do_delete(stage, id), do: if(elem(stage, 0) === id, do: nil, else: stage)
end
