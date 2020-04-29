defmodule Sage.Test.Assertions do
  defmacro assert_state(state, pattern) do
    quote do
      if match?({%ExUnit.AssertionError{}, _}, unquote(state).last_result) do
        {error, stacktrace} = unquote(state).last_result
        reraise error, stacktrace
      end

      assert unquote(state).aborted? == false
      assert unquote(pattern) = unquote(state)
    end
  end
end
