defmodule Sagax.Test.Builder do
  alias __MODULE__
  alias Sagax.Test.Log

  import ExUnit.Assertions
  import Sagax.Test.Assertions

  defstruct log: nil, args: nil, context: nil

  def new_builder(opts), do: struct!(Builder, opts)

  def effect(builder, value, outer_opts \\ []) do
    fn results, args, context, opts ->
      if Keyword.has_key?(outer_opts, :results) do
        assert_saga_results results, Keyword.get(outer_opts, :results, [])
      end

      if Keyword.has_key?(outer_opts, :opts) do
        assert Enum.all?(Keyword.get(outer_opts, :opts), fn {k, v} ->
                 Keyword.get(opts, k) === v
               end),
               message: "Expected opts to match",
               left: opts,
               right: Keyword.get(outer_opts, :opts)
      end

      if Keyword.get(outer_opts, :delay, true) do
        Process.sleep(:rand.uniform(250))
      end

      assert args == Keyword.get(outer_opts, :args, Map.get(builder, :args))
      assert context == Keyword.get(outer_opts, :context, Map.get(builder, :context))

      if Keyword.has_key?(outer_opts, :tag) do
        {:ok, Log.log(builder.log, value), Keyword.get(outer_opts, :tag)}
      else
        {:ok, Log.log(builder.log, value)}
      end
    end
  end

  def effect_error(builder, value, outer_opts \\ []) do
    fn results, args, context, opts ->
      if Keyword.has_key?(outer_opts, :results) do
        assert_saga_results results, Keyword.get(outer_opts, :results, [])
      end

      if Keyword.has_key?(outer_opts, :opts) do
        assert Enum.all?(Keyword.get(outer_opts, :opts), fn {k, v} ->
                 Keyword.get(opts, k) === v
               end),
               message: "Expected opts to match",
               left: opts,
               right: Keyword.get(outer_opts, :opts)
      end

      if Keyword.get(outer_opts, :delay, true) do
        Process.sleep(:rand.uniform(250))
      end

      assert args == Keyword.get(outer_opts, :args, Map.get(builder, :args))
      assert context == Keyword.get(outer_opts, :context, Map.get(builder, :context))

      {:error, Log.log(builder.log, value)}
    end
  end

  def compensation(builder, value, outer_opts \\ []) do
    fn result, results, args, context, opts ->
      assert result == value,
        message: "Expected the result of the effect to compensate to match",
        left: result,
        right: value

      if Keyword.has_key?(outer_opts, :results) do
        assert_saga_results results, Keyword.get(outer_opts, :results, [])
      end

      if Keyword.has_key?(outer_opts, :opts) do
        assert Enum.all?(Keyword.get(outer_opts, :opts), fn {k, v} ->
                 Keyword.get(opts, k) === v
               end),
               message: "Expected opts to match",
               left: opts,
               right: Keyword.get(outer_opts, :opts)
      end

      if Keyword.get(outer_opts, :delay, true) do
        Process.sleep(:rand.uniform(250))
      end

      assert args == Keyword.get(outer_opts, :args, Map.get(builder, :args))
      assert context == Keyword.get(outer_opts, :context, Map.get(builder, :context))

      Log.log(builder.log, "#{value}.comp")

      Keyword.get(outer_opts, :result, :ok)
    end
  end
end
