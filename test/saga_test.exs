defmodule SagaxTest do
  use ExUnit.Case

  describe "new()" do
    test "sets :max_concurrency to System.schedulers_online() by default" do
      saga = Sagax.new()
      assert Keyword.get(saga.opts, :max_concurrency) == System.schedulers_online()
    end

    test "allows to initialize args" do
      saga = Sagax.new(args: %{some: "arg"})
      assert saga.args == %{some: "arg"}
      refute Keyword.has_key?(saga.opts, :args)
    end

    test "allows to initialize context" do
      saga = Sagax.new(context: %{some: "context"})
      assert saga.context == %{some: "context"}
      refute Keyword.has_key?(saga.opts, :context)
    end

    test "allows to set :max_concurrency" do
      saga = Sagax.new(max_concurrency: 1000)
      assert Keyword.get(saga.opts, :max_concurrency) == 1000
    end
  end

  describe "inherit()" do
    test "sets the args and context when uninitialized" do
      saga_1 = Sagax.new()
      saga_2 = Sagax.new() |> Sagax.put_args(%{a: "b"}) |> Sagax.put_context(%{c: "d"})
      assert saga = Sagax.inherit(saga_1, saga_2)
      assert saga.args == %{a: "b"}
      assert saga.context == %{c: "d"}
    end

    test "ignores initialized args" do
      saga_1 = Sagax.new() |> Sagax.put_args(%{a: "b1"})
      saga_2 = Sagax.new() |> Sagax.put_args(%{a: "b2"})
      assert saga = Sagax.inherit(saga_1, saga_2)
      assert saga.args == %{a: "b1"}
    end

    test "ignores initialized context" do
      saga_1 = Sagax.new() |> Sagax.put_context(%{c: "d1"})
      saga_2 = Sagax.new() |> Sagax.put_context(%{c: "d2"})
      assert saga = Sagax.inherit(saga_1, saga_2)
      assert saga.context == %{c: "d1"}
    end
  end

  describe "put_args()" do
    test "sets args" do
      saga = Sagax.new()
      assert saga.args == nil
      saga = Sagax.put_args(saga, %{some: "arg"})
      assert saga.args == %{some: "arg"}
    end
  end

  describe "put_new_args()" do
    test "sets args if they are nil" do
      saga = Sagax.new() |> Sagax.put_new_args(%{some: "arg"})
      assert %Sagax{args: %{some: "arg"}} = saga
      saga = Sagax.new(args: %{some: "arg1"}) |> Sagax.put_new_args(%{some: "arg2"})
      assert %Sagax{args: %{some: "arg1"}} = saga
    end
  end

  describe "put_context()" do
    test "sets context" do
      saga = Sagax.new()
      assert saga.context == nil
      saga = Sagax.put_context(saga, %{some: "context"})
      assert saga.context == %{some: "context"}
    end
  end

  describe "put_new_context()" do
    test "sets context if they are nil" do
      saga = Sagax.new() |> Sagax.put_new_context(%{some: "context"})
      assert %Sagax{context: %{some: "context"}} = saga
      saga = Sagax.new(context: %{some: "context1"}) |> Sagax.put_new_context(%{some: "context2"})
      assert %Sagax{context: %{some: "context1"}} = saga
    end
  end

  describe "execute()" do
    test "returns the saga" do
      {:ok, saga} =
        Sagax.new()
        |> Sagax.add(fn _, _, _, _ -> {:ok, "a"} end)
        |> Sagax.add(fn _, _, _, _ -> {:ok, "b", :tag} end)
        |> Sagax.add(fn _, _, _, _ -> {:ok, "c", {:namespace, "tag"}} end)
        |> Sagax.execute(%{})

      assert %Sagax{} = saga
      assert Sagax.all(saga) == ["a", {"b", :tag}, {"c", {:namespace, "tag"}}]
    end

    test "does not shallow exceptions by default" do
      assert_raise(RuntimeError, "exception", fn ->
        Sagax.new()
        |> Sagax.add(fn _, _, _, _ -> raise "exception" end)
        |> Sagax.execute(%{})
      end)
    end

    test "allows to overwrite args" do
      saga = Sagax.new() |> Sagax.put_args(%{a: "b"}) |> Sagax.execute()
      assert {:ok, %Sagax{args: %{a: "b"}}} = saga

      saga = Sagax.new() |> Sagax.put_args(%{a: "b"}) |> Sagax.execute(%{a: "c"})
      assert {:ok, %Sagax{args: %{a: "c"}}} = saga
    end

    test "allows to overwrite context" do
      saga = Sagax.new() |> Sagax.put_context(%{c: "d"}) |> Sagax.execute()
      assert {:ok, %Sagax{context: %{c: "d"}}} = saga

      saga = Sagax.new() |> Sagax.put_context(%{c: "d"}) |> Sagax.execute(%{}, %{c: "e"})
      assert {:ok, %Sagax{context: %{c: "e"}}} = saga
    end
  end

  describe "find()" do
    test "returns the first result with a matching tag" do
      saga = %Sagax{results: ["a", {"b", :tag}, {"c", "tag"}, {"d", {"ns", "tag"}}]}
      assert Sagax.find(saga, :tag) == "b"
      assert Sagax.find(saga, "tag") == "c"
      assert Sagax.find(saga, {:_, "tag"}) == "d"
    end

    test "returns the first result with a matching namespace and tag" do
      saga = %Sagax{results: ["a", {"b", {"ns", :tag}}, {"c", :tag}]}
      assert Sagax.find(saga, {"ns", :_}) == "b"
    end
  end

  describe "all()" do
    test "returns all results with a matching tag" do
      saga = %Sagax{results: ["a", {"b", :tag}, {"c", :tag}, {"d", {"ns", :tag}}]}
      assert Sagax.all(saga, :tag) == ["b", "c", "d"]
      assert Sagax.all(saga, {:_, :tag}) == ["d"]
      assert Sagax.all(saga, {"ns", :tag}) == ["d"]
      assert Sagax.all(saga, {"ns", :_}) == ["d"]
      assert Sagax.all(saga, "a") == []
    end
  end
end
