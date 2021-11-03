defmodule Sagax.Next.Error do
  defexception [:path, :error]

  def message(exception) do
    exception.error
  end
end
