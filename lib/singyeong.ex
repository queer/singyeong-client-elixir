defmodule Singyeong do
  @moduledoc """
  Helper functions to make a 신경 connection go!
  """

  @doc """
  Parses a 신경 DSN into a format usable by the client. Returns a tuple of
  `{app_id, password | nil, host, port, scheme}`. Encoding is ignored, as this
  client will always use ETF for communication.

  ## Examples

      iex> Singyeong.parse_dsn("singyeong://test@localhost")
      {"test", nil, "localhost", 80, "ws"}

      iex> Singyeong.parse_dsn("ssingyeong://test:pass-word@localhost")
      {"test", "pass-word", "localhost", 80, "wss"}

      iex> Singyeong.parse_dsn("singyeong://test@localhost:4567")
      {"test", nil, "localhost", 4567, "ws"}

      iex> Singyeong.parse_dsn("ssingyeong://test:pass~-word@localhost:4921/")
      {"test", "pass~-word", "localhost", 4921, "wss"}

      iex> Singyeong.parse_dsn("singyeong://test:pass@localhost:21312?encoding=json")
      {"test", "pass", "localhost", 21312, "ws"}

      iex> Singyeong.parse_dsn("ssingyeong://test:pass@host:12321/?encoding=etf")
      {"test", "pass", "host", 12321, "wss"}

      iex> Singyeong.parse_dsn("ssssssssingyeong://invalid:invalid@invalid:4567/?encoding=msgpack")
      ** (ArgumentError) dsn: invalid protocol: ssssssssingyeong
  """
  @spec parse_dsn(String.t()) :: {String.t(), String.t() | nil, String.t(), non_neg_integer(), String.t()}
  def parse_dsn(dsn) do
    uri = URI.parse dsn
    protocol =
      case uri.scheme do
        "singyeong" -> "ws"
        "ssingyeong" -> "wss"
        _ -> raise ArgumentError, "dsn: invalid protocol: #{uri.scheme}"
      end

    [app_id, password] =
      case String.split(uri.userinfo, ":", parts: 2) do
        [app_id] -> [app_id, nil]
        [app_id, password] -> [app_id, password]
      end

    if app_id == nil do
      raise ArgumentError, "app_id: cannot be nil"
    end

    {app_id, password, uri.host, uri.port || 80, protocol}
  end
end
