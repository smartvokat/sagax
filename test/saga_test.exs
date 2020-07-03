defmodule SagaxTest do
  use ExUnit.Case

  describe "new()" do
    test "sets :max_concurrency to System.schedulers_online() by default" do
      saga = Sagax.new()
      assert Keyword.get(saga.opts, :max_concurrency) == System.schedulers_online()
    end

    test "allows to set :max_concurrency" do
      saga = Sagax.new(max_concurrency: 1000)
      assert Keyword.get(saga.opts, :max_concurrency) == 1000
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
