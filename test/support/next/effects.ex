defmodule Sagax.Next.Test.Effects do
  import ExUnit.Assertions
  require ExUnit.Assertions

  def assert_value_effect(right, result \\ :ok) do
    fn left ->
      assert left == right
      result
    end
  end
end
