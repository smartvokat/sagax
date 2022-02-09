defmodule Sagax.Next.BuilderTest do
  alias Sagax.Next, as: Sagax

  use ExUnit.Case

  describe "execute/3" do
    test "executes a succesful saga" do
      defmodule OkSaga do
        use Sagax.Builder

        def new(args, context, opts) do
          Sagax.new(args: args, context: context, opts: opts)
          |> Sagax.put("a", fn -> {:ok, "a"} end)
          |> Sagax.put("b", fn -> {:ok, "b"} end)
        end
      end

      {:ok, values, context} = OkSaga.execute(%{}, %{}, [])

      assert values == %{"a" => "a", "b" => "b"}
      assert context == %{}
    end

    test "executes a erroneous saga" do
      defmodule ErrorSaga do
        use Sagax.Builder

        def new(args, context, opts) do
          Sagax.new(args: args, context: context, opts: opts)
          |> Sagax.put("a", fn -> {:ok, "a"} end)
          |> Sagax.put("b", fn -> {:error, "b"} end)
        end
      end

      {:error, errors, context} = ErrorSaga.execute(%{}, %{}, [])

      assert [%Sagax.Error{error: "b", path: "b"}] = errors
      assert context == %{}
    end

    test "executes a halted saga" do
      defmodule HaltSaga do
        use Sagax.Builder

        def new(args, context, opts) do
          Sagax.new(args: args, context: context, opts: opts)
          |> Sagax.put("a", fn -> {:ok, "a"} end)
          |> Sagax.put("b", fn -> {:halt, "b"} end)
          |> Sagax.put("c", fn -> {:ok, "c"} end)
        end
      end

      {:halt, values, context} = HaltSaga.execute(%{}, %{}, [])

      assert values == %{"a" => "a", "b" => "b"}
      assert context == %{}
    end

    test "returns context as 3rd tuple element" do
      defmodule MetaSaga do
        use Sagax.Builder

        def new(args, context, opts) do
          Sagax.new(args: args, context: context, opts: opts)
          |> Sagax.put("a", fn -> {:ok, "a", %{some: "context"}} end)
          |> Sagax.put("b", fn -> {:ok, "b", %{more: "context"}} end)
        end
      end

      {:ok, values, context} = MetaSaga.execute(%{}, %{ctx: %{my: "context"}}, [])

      assert values == %{"a" => "a", "b" => "b"}
      assert %{ctx: %{my: "context"}, some: "context", more: "context"} = context
    end
  end

  describe "use/3" do
    test "supports an empty builder" do
      defmodule Use1Saga do
        use Sagax.Builder

        def new(args, context, opts) do
          Sagax.new(args: args, context: context, opts: opts)
          |> Sagax.put("a", fn -> {:ok, "a"} end)
          |> Sagax.put("b", fn -> {:ok, "b"} end)
        end
      end

      assert %Sagax{value: %{"ab" => %{"a" => "a", "b" => "b"}}} =
               Sagax.new()
               |> Sagax.put("ab", Use1Saga.use())
               |> Sagax.execute()
    end

    test "supports args and opts modification" do
      defmodule Use2Saga do
        use Sagax.Builder

        def new(args, _context, opts) do
          assert %{hello: "world"} = args
          assert [foo: :bar] = opts
        end
      end

      Sagax.new(args: %{greeting: "world"})
      |> Sagax.run(Use2Saga.use(fn _, args -> %{hello: args.greeting} end, foo: :bar))
      |> Sagax.execute()
    end
  end
end
