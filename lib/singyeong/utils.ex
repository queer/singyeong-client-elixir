defmodule Singyeong.Utils do
  def stringify_keys(map, recurse? \\ false)

  def stringify_keys(map, recurse?) when is_map(map) do
    map
    |> Enum.map(fn {k, v} ->
      if is_binary(k) do
        {k, stringify_keys(v)}
      else
        if recurse? do
          {Atom.to_string(k), stringify_keys(v)}
        else
          {Atom.to_string(k), v}
        end
      end
    end)
    |> Enum.into(%{})
  end

  def stringify_keys(not_map, _), do: not_map
end
