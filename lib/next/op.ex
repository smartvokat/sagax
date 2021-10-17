defmodule Sagax.Next.Op do
  @moduledoc false

  alias Sagax.Next, as: Sagax
  alias Sagax.Utils

  require Record

  @type effect :: any()
  @type compensation :: any()
  @type t() ::
          record(:op,
            id: binary(),
            type: atom(),
            opts: keyword(),
            effect: effect(),
            comp: compensation(),
            saga_id: binary() | nil
          )

  Record.defrecord(:op,
    id: nil,
    type: nil,
    opts: nil,
    effect: nil,
    comp: nil,
    saga_id: nil
  )

  @doc """
  Checks if the given `op` is a `Sagax.Op` record at all and optionally if it is of a
  specified `type`.
  """
  defguard is_op(operation) when Record.is_record(operation, :op)

  defguard is_op(operation, type)
           when Record.is_record(operation, :op) and op(operation, :type) == type

  defguard is_noop(operation)
           when Record.is_record(operation, :op) and op(operation, :comp) == :noop

  @doc """
  Creates a new put operation.
  """
  @spec new_put_op(binary(), atom(), effect(), compensation()) :: Op.t()
  def new_put_op(saga_id, key, effect, comp \\ :noop),
    do:
      op(
        id: Utils.new_id(),
        type: :put,
        opts: [key: key],
        effect: effect,
        comp: comp,
        saga_id: saga_id
      )

  @doc """
  Adds an effect to run as part of the saga without storing its result.
  """
  @spec new_run_op(binary(), effect(), compensation()) :: Op.t()
  def new_run_op(saga_id, effect, comp \\ :noop),
    do: op(id: Utils.new_id(), type: :run, effect: effect, comp: comp, saga_id: saga_id)

end
