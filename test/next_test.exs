defmodule Sagax.NextTest do
  alias Sagax.Next, as: Sagax
  alias Sagax.Op

  require Sagax.Op

  use ExUnit.Case

  describe "new()" do
    test "initializes without args" do
      assert saga = Sagax.new()
      assert saga.args == nil
    end
  end

  describe "put()" do
    test "adds the op correctly" do
      assert saga = Sagax.put(Sagax.new(), :hello, &IO.puts/1)
      assert length(saga.ops) == 1
      assert Op.op(Enum.at(saga.ops, 0), :type) == :put
      assert Op.op(Enum.at(saga.ops, 0), :opts) == [key: :hello]
    end
  end

  describe "run()" do
    test "adds the op correctly" do
      effect = fn _, _ -> nil end
      comp = fn _, _, _ -> nil end

      assert saga = Sagax.run(Sagax.new(), effect, comp)
      assert length(saga.ops) == 1
      assert Op.op(Enum.at(saga.ops, 0), :type) == :run
      assert Op.op(Enum.at(saga.ops, 0), :effect) == effect
      assert Op.op(Enum.at(saga.ops, 0), :comp) == comp
    end
  end
end
