defmodule Sagax.Next.Builder do
  alias Sagax.Next, as: Sagax

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      @doc """
      Initiates and executes the saga with the given `args` and `context`.
      """
      @spec execute(map(), map(), Keyword.t()) :: {:ok, any()} | {:error, [Sagax.Next.Error.t()]}
      def execute(args, context, opts \\ []) do
        saga =
          args
          |> new(context, opts)
          |> Sagax.execute()

        if Enum.any?(saga.errors) do
          {:error, saga.errors}
        else
          {:ok, saga}
        end
      end
    end
  end

  @callback new(any, any, []) :: Sagax.t()
end
