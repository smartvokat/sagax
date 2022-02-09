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

        case saga.state do
          :error ->
            {:error, saga.errors, saga.context}

          _ ->
            {saga.state, saga.value, saga.context}
        end
      end

      @doc """
      Enables composition with new `args` based on the current values. The
      `builder` function receives the same arguments as any other effect
      (values, args, context).
      """
      @spec compose(Sagax.Next.Op.effect(), Keyword.t()) :: Sagax.Next.Op.effect()
      def compose(builder \\ nil, opts \\ [])

      def compose(nil, opts) do
        fn saga, args, context ->
          apply(__MODULE__, :new, [args, context, opts])
        end
      end

      def compose(builder, opts) do
        fn saga, args, context ->
          args =
            cond do
              is_function(builder, 1) ->
                apply(builder, [saga])

              is_function(builder, 2) ->
                apply(builder, [saga, args])

              is_function(builder, 3) ->
                apply(builder, [saga, args, context])

              true ->
                raise ArgumentError,
                      "Expected builder function to be a function with arity 1,2, or 3"
            end

          apply(__MODULE__, :new, [args, context, opts])
        end
      end
    end
  end

  @callback new(any, any, []) :: Sagax.Next.t()
end
