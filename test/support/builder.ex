defmodule Sagax.Test.Builder do
  alias __MODULE__
  alias Sagax.Test.Log

  import ExUnit.Assertions
  import Sagax.Test.Assertions

  defstruct log: nil, args: nil, context: nil

  def new_builder(opts), do: struct!(Builder, opts)

  def effect(builder, value, opts \\ []) do
    fn results, args, context, _opts ->
      if Keyword.has_key?(opts, :results) do
        assert_saga_results results, Keyword.get(opts, :results, [])
      end

      if Keyword.get(opts, :delay, true) do
        Process.sleep(:rand.uniform(250))
      end

      assert args == Keyword.get(opts, :args, Map.get(builder, :args))
      assert context == Keyword.get(opts, :context, Map.get(builder, :context))

      if Keyword.has_key?(opts, :tag) do
        {:ok, Log.log(builder.log, value), Keyword.get(opts, :tag)}
      else
        {:ok, Log.log(builder.log, value)}
      end
    end
  end

  def effect_error(builder, value, opts \\ []) do
    fn results, args, context, _opts ->
      if Keyword.has_key?(opts, :results) do
        assert_saga_results results, Keyword.get(opts, :results, [])
      end

      if Keyword.get(opts, :delay, true) do
        Process.sleep(:rand.uniform(250))
      end

      assert args == Keyword.get(opts, :args, Map.get(builder, :args))
      assert context == Keyword.get(opts, :context, Map.get(builder, :context))

      {:error, Log.log(builder.log, value)}
    end
  end

  def compensation(builder, value, opts \\ []) do
    fn result, results, args, context, _opts ->
      assert result == value,
        message: "Expected the result of the effect to compensate to match",
        left: result,
        right: value

      if Keyword.has_key?(opts, :results) do
        assert_saga_results results, Keyword.get(opts, :results, [])
      end

      if Keyword.get(opts, :delay, true) do
        Process.sleep(:rand.uniform(250))
      end

      assert args == Keyword.get(opts, :args, Map.get(builder, :args))
      assert context == Keyword.get(opts, :context, Map.get(builder, :context))

      Log.log(builder.log, "#{value}.comp")

      Keyword.get(opts, :result, :ok)
    end
  end
end
