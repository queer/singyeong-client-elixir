defmodule Singyeong.Payload do
  use TypedStruct

  typedstruct do
    field :op, non_neg_integer(), enforce: true
    field :t, String.t() | nil
    field :d, term(), enforce: true
  end
end
