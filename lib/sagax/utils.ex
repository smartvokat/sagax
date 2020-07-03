defmodule Sagax.Utils do
  @moduledoc false

  def peek_id([stage | _]), do: elem(stage, 0)
  def peek_id(_), do: nil

  def peek_effect([stage | _]), do: elem(stage, 1)
  def peek_effect(_), do: nil

  def delete(%Sagax{} = saga, id), do: %{saga | queue: delete(saga.queue, id)}
  def delete({left_id, _}, right_id) when left_id == right_id, do: nil
  def delete({left_id, _, _, _}, right_id) when left_id == right_id, do: nil
  def delete({_, %Sagax{} = saga, _, _} = stage, id), do: put_elem(stage, 1, delete(saga, id))

  def delete({_, effects} = stage, id) when is_list(effects),
    do: put_elem(stage, 1, delete(effects, id))

  def delete(effects, id) when is_list(effects),
    do: Enum.map(effects, &delete(&1, id)) |> Enum.reject(&is_nil/1)

  def delete(stage, _), do: stage
end
