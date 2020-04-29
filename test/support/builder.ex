defmodule Sagax.Test.Builder do
  alias __MODULE__
  alias Sagax.Test.Log

  import ExUnit.Assertions

  defstruct log: nil, args: %{}, context: nil

  def new_builder(opts), do: struct!(Builder, opts)

  def sync_effect(builder, value, opts \\ []) do
    fn results, args, context ->
      assert results == Keyword.get(opts, :results, [])
      assert args == Map.get(builder, :args, %{})
      assert context == Map.get(builder, :context, nil)
      {:ok, Log.sync(builder.log, value)}
    end
  end

  @spec sync_effect_error(any, any, any) :: (any, any, any -> {:error, any})
  def sync_effect_error(builder, value, opts \\ []) do
    fn results, args, context ->
      assert results == Keyword.get(opts, :results, [])
      assert args == Map.get(builder, :args, %{})
      assert context == Map.get(builder, :context, nil)
      {:error, Log.sync(builder.log, value)}
    end
  end

  def sync_comp(builder, value, opts \\ []) do
    fn result, results, args, context ->
      assert result == value
      assert results == Keyword.get(opts, :results, [])
      assert args == Map.get(builder, :args, %{})
      assert context == Map.get(builder, :context, nil)
      Log.sync(builder.log, "#{value}.comp")
      :ok
    end
  end
end
