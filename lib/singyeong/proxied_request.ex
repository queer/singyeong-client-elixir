defmodule Singyeong.ProxiedRequest do
  use TypedStruct
  alias Singyeong.Query

  typedstruct enforce: true do
    field :method, String.t()
    field :route, String.t()
    field :body, term(),
    field :query, Query.t()
  end
end
