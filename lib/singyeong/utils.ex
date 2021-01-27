defmodule Singyeong.Utils do
  @events %{
    "SEND" => :send,
    "BROADCAST" => :broadcast,
    "QUEUE" => :queue,
    "QUEUE_CONFIRM" => :queue_confirm,
  }

  def stringify_keys(map, recurse? \\ false)

  def stringify_keys(map, recurse?) when is_map(map) and not is_struct(map) do
    map
    |> Enum.map(fn {k, v} ->
      cond do
        is_binary(k) and not recurse? ->
          {k, v}

        is_binary(k) and recurse? ->
          {k, stringify_keys(v, true)}

        is_atom(k) and not recurse? ->
          {Atom.to_string(k), v}

        is_atom(k) and recurse? ->
          {Atom.to_string(k), stringify_keys(v, true)}
      end
    end)
    |> Enum.into(%{})
  end

  def stringify_keys(struct, recurse?) when is_struct(struct) do
    struct
    |> Map.from_struct
    |> stringify_keys(recurse?)
  end

  def stringify_keys(not_map, _), do: not_map

  def event_name_to_atom(event) do
    Map.get(@events, event, nil) || raise ArgumentError, "event: unknown type: #{inspect event}"
  end
end
