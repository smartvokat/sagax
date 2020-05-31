defmodule SagaxTest do
  use ExUnit.Case

  # describe "run()" do
  #   test "appends functions correctly" do
  #     saga = Sagax.new() |> Sagax.run(&IO.inspect/2) |> Sagax.run(&IO.inspect/2)
  #     assert saga.stages == [{&IO.inspect/2, :noop}, {&IO.inspect/2, :noop}]
  #   end
  # end

  # describe "run_async()" do
  #   test "works with empty sagas" do
  #     saga = Sagax.new() |> Sagax.run_async(&IO.inspect/2)
  #     assert saga.stages == [[{&IO.inspect/2, :noop}]]
  #   end

  #   test "allows combinations of run() and run_async()" do
  #     saga =
  #       Sagax.new()
  #       |> Sagax.run(&IO.inspect/1)
  #       |> Sagax.run_async(&IO.puts/1)
  #       |> Sagax.run_async(&IO.puts/1)
  #       |> Sagax.run_async(Sagax.new())
  #       |> Sagax.run(&IO.inspect/1)
  #       |> Sagax.run_async(Sagax.new())
  #       |> Sagax.run(Sagax.new())
  #       |> Sagax.run_async(&IO.inspect/2)
  #       |> Sagax.run_async(&IO.inspect/2)

  #     assert saga.stages == [
  #              [{&IO.inspect/2, :noop}, {&IO.inspect/2, :noop}],
  #              {%Sagax{}, :noop},
  #              [{%Sagax{}, :noop}],
  #              {&IO.inspect/1, :noop},
  #              [{%Sagax{}, :noop}, {&IO.puts/1, :noop}, {&IO.puts/1, :noop}],
  #              {&IO.inspect/1, :noop}
  #            ]
  #   end
  # end
end
