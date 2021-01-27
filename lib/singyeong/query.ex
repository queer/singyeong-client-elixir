defmodule Singyeong.Query do
  use TypedStruct

  @boolean_op_names [
    :"$eq",
    :"$ne",
    :"$gt",
    :"$gte",
    :"$lt",
    :"$lte",
    :"$in",
    :"$nin",
    :"$contains",
    :"$ncontains",
  ]
  @logical_op_names [
    :"$and",
    :"$or",
    :"$nor",
  ]
  @selector_names [
    :"$min",
    :"$max",
    :"$avg",
  ]

  @type ops() :: [op()] | []
  @type boolean_op_name() ::
    :"$eq"
    | :"$ne"
    | :"$gt"
    | :"$gte"
    | :"$lt"
    | :"$lte"
    | :"$in"
    | :"$nin"
    | :"$contains"
    | :"$ncontains"

  @type logical_op_name() ::
    :"$and"
    | :"$or"
    | :"$nor"

  @type boolean_op() :: %{
    required(boolean_op_name()) => term()
  }

  @type logical_op() :: %{
    required(logical_op_name()) => maybe_improper_list(boolean_op(), logical_op())
  }

  @type op() :: %{
    required(binary()) => boolean_op() | logical_op()
  }

  @type selector() ::
    :"$min"
    | :"$max"
    | :"$avg"

  typedstruct do
    field :application, String.t() | nil
    field :restricted, boolean(), default: false
    field :key, String.t() | nil, default: nil
    field :droppable, boolean(), default: false
    field :optional, boolean(), default: false
    field :ops, [op()], default: []
    field :selector, selector() | nil, default: nil
  end

  @doc """
  Creates a new query for the given target application
  """
  @spec new(String.t() | nil) :: __MODULE__.t()
  def new(name), do: %__MODULE__{application: name}

  @doc """
  Converts the provided values into a proper boolean op.
  """
  @spec values_to_op(boolean_op_name(), String.t(), term()) :: boolean_op()
  def values_to_op(op, key, value), do: %{key => %{op => value}}

  @doc """
  Adds the provided boolean op to the query.
  """
  @spec with_op(__MODULE__.t(), boolean_op_name(), String.t(), term()) :: __MODULE__.t()
  def with_op(%__MODULE__{ops: ops} = query, op, key, value) when op in @boolean_op_names do
    %{query | ops: ops ++ [values_to_op(op, key, value)]}
  end

  @doc """
  Adds the provided boolean op to the query.
  """
  @spec with_op(__MODULE__.t(), boolean_op()) :: __MODULE__.t()
  def with_op(%__MODULE__{ops: ops} = query, op) when op in @boolean_op_names do
    %{query | ops: ops ++ [op]}
  end

  @doc """
  Adds the provided logical op over the provided ops to the query.
  """
  @spec with_logical_op(__MODULE__.t(), logical_op_name(), op(), op()) :: __MODULE__.t()
  def with_logical_op(%__MODULE__{ops: ops} = query, logical_op, op1, op2) when logical_op in @logical_op_names do
    %{query | ops: ops ++ [%{logical_op => [op1, op2]}]}
  end

  @doc """
  Sets the query's selector to the specified key
  """
  @spec with_selector(__MODULE__.t(), selector(), String.t()) :: __MODULE__.t()
  def with_selector(%__MODULE__{} = query, selector, key) when is_nil(selector) or selector in @selector_names do
    if is_nil(selector) do
      %{query | selector: nil}
    else
      %{query | selector: %{selector => key}}
    end
  end
end
