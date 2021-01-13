defmodule Singyeong.Client do
  use GenServer
  alias Singyeong.{
    Metadata,
    Payload,
    ProxiedRequest,
    Query,
    Utils,
  }
  require Logger

  @type http_method() ::
      :get
      | :post
      | :put
      | :patch
      | :delete

  ###############
  ## WEBSOCKET ##
  ###############

  @op_hello         0
  @op_identify      1
  @op_ready         2
  @op_invalid       3
  @op_dispatch      4
  @op_heartbeat     5
  @op_heartbeat_ack 6
  @op_goodbye       7
  @op_error         8


  def start_link({app_id, password, host, port, _scheme}) do
    uri = "#{host}:#{port}/gateway/websocket"
    Logger.debug "[신경] client: starting link, uri=#{uri}."
    GenServer.start_link __MODULE__, %{
      app_id: app_id,
      password: password,
      uri: uri,
      host: host,
      port: port,
      scheme: scheme,
    }, name: __MODULE__
  end

  @impl GenServer
  def init(%{
    app_id: app_id,
    password: password,
    uri: uri,
    host: host,
    port: port,
    scheme: scheme,
  }) do
    :ets.new :singyeong, [:named_table, :set, :public, read_concurrency: true]
    :ets.insert :singyeong, {:app_id,   app_id}
    :ets.insert :singyeong, {:password, password}
    :ets.insert :singyeong, {:host,     host}
    :ets.insert :singyeong, {:port,     port}
    :ets.insert :singyeong, {:ssl,      scheme == "wss"}

    state =
      %{
        app_id: app_id,
        client_id: id(32),
        auth: password,
        uri: uri,
        port: port,
        conn: nil,
      }

    Logger.debug "[신경] client: init: ready for payloads."

    {:ok, state, {:continue, :connect}}
  end

  @impl GenServer
  def handle_continue(:connect, %{port: port, uri: uri} = state) do
    {:ok, worker} =
      uri
      |> :binary.bin_to_list
      |> :gun.open(port)

    {:ok, :http} = :gun.await_up worker, 5_000
    stream = :gun.ws_upgrade worker, "?encoding=etf"
    await_ws_upgrade worker, stream
    state = %{state | conn: worker}
    {:noreply, state}
  end

  defp await_ws_upgrade(worker, stream) do
    Logger.debug "[신경] connect: awaiting ws upgrade"
    receive do
      {:gun_upgrade, ^worker, ^stream, [<<"websocket">>], _headers} ->
        Logger.debug "[신경] connect: :gun_upgrade"
        :ok

      {:gun_error, ^worker, ^stream, reason} ->
        Logger.error "[신경] connect: :gun_error: #{inspect reason, pretty: true}"
        exit {:ws_upgrade_failed, reason}
    after
      5000 ->
        Logger.error "[신경] connect: cannot upgrade: timeout after 5 seconds"

        exit :timeout
    end
  end

  @impl GenServer
  def handle_info({:gun_ws, _worker, _stream, {:binary, frame}}, state) do
    # TODO: This is unsafe
    payload = :erlang.binary_to_term frame
    try do
      case process_frame(payload[:op], payload, state) do
        {:reply, reply, new_state} ->
          out = __MODULE__.reply reply
          {:reply, out, new_state}

        {:ok, _} = ok ->
          ok

        {:noreply, new_state} ->
          {:ok, new_state}

        {:close, _} = close ->
          close
      end
    rescue
      e ->
        Logger.error "[신경] payload: error processing: #{inspect e, pretty: true}"
        Logger.error "[신경] payload: #{inspect payload, pretty: true}"
        Logger.error "[신경] #{inspect __STACKTRACE__}"
        {:ok, state}
    end
  end

  def handle_info({:gun_ws, _conn, _stream, {:close, code, reason}}, state) do
    Logger.warn "[신경] disconnect: code #{code}, reason #{inspect reason}"
    {:noreply, state}
  end

  def handle_info({:gun_down, _conn, _proto, _reason, _, _}, state) do
    # TODO: Use a real timer to cancel heartbeat task
    {:noreply, state}
  end

  def handle_info({:gun_up, worker, _proto}, state) do
    stream = :gun.ws_upgrade worker, state.uri
    await_ws_upgrade worker, stream
    Logger.warn "[신경] Reconnected after connection broke"
    {:noreply, %{state | heartbeat_ack: true}}
  end

  defp process_frame(@op_hello, frame, %{app_id: app_id, client_id: client_id, auth: auth} = state) do
    interval = frame.d["heartbeat_interval"]
    Logger.debug "[신경] heartbeat: interval=#{interval}"
    Process.send_after self(), {:heartbeat, interval}, interval
    Logger.debug "[신경] heartbeat: loop started"
    reply =
      %Payload{
        op: @op_identify,
        d: %{
          application_id: app_id,
          client_id: client_id,
          auth: auth,
        }
      }

    # process_frame doesn't need the special stuff
    {:reply, reply, state}
  end

  defp process_frame(@op_ready, _, state) do
    Logger.info "[신경] connect: ready."
    Logger.info "[신경] connect: welcome to 신경."
    {:noreply, state}
  end

  defp process_frame(@op_heartbeat_ack, _frame, state) do
    Logger.debug "[신경] heartbeat: ack"
    {:noreply, state}
  end

  defp process_frame(@op_dispatch, frame, state) do
    Logger.debug "[신경] dispatch: frame: #{inspect frame}"
    event =
      case Utils.event_name_to_atom(frame.t) do
        :send ->
          {:send, frame.d["nonce"], frame.d["payload"]}

        :broadcast ->
          {:broadcast, frame.d["nonce"], frame.d["payload"]}

        :queue ->
          {:queue, frame.d["payload"]["queue"], frame.d["nonce"], frame.d["payload"]["payload"]}

        :queue_confirm ->
          {:queue_confirm, frame.d["queue"]}
      end

    Singyeong.Producer.notify event
    {:noreply, state}
  end

  defp process_frame(op, frame, state) do
    Logger.warn "[신경] payload: unknown op: #{op}"
    Logger.warn "[신경] payload: suspect frame: #{inspect frame, pretty: true}"

    {:ok, state}
  end

  def handle_cast({:heartbeat, interval}, _ws, %{client_id: client_id} = state) do
    reply =
      %Payload{
        op: @op_heartbeat,
        d: %{
          client_id: client_id,
        }
      }

    Logger.debug "[신경] heartbeat: sending"
    :gun_ws.send state.conn, reply(reply)
    Process.send_after self(), {:heartbeat, interval}, interval

    {:noreply, state}
  end

  def handle_cast({:send, nonce, query, payload}, _ws, state) do
    reply =
      %Payload{
        op: @op_dispatch,
        t: "SEND",
        d: %{
          target: query,
          nonce: nonce,
          payload: payload,
        },
      }

    Logger.debug "[신경] send: dispatching"
    :gun_ws.send state.conn, reply(reply)
    {:noreply, state}
  end

  def handle_cast({:broadcast, nonce, query, payload}, _ws, state) do
    reply =
      %Payload{
        op: @op_dispatch,
        t: "BROADCAST",
        d: %{
          target: query,
          nonce: nonce,
          payload: payload,
        },
      }

    Logger.debug "[신경] broadcast: dispatching"
    :gun_ws.send state.conn, reply(reply)
    {:noreply, state}
  end

  def handle_cast({:queue, queue, nonce, query, payload}, _ws, state) do
    reply =
      %Payload{
        op: @op_dispatch,
        t: "QUEUE",
        d: %{
          queue: queue,
          nonce: nonce,
          target: query,
          payload: payload,
        },
      }

    Logger.debug "[신경] queue: dispatching"
    :gun_ws.send state.conn, reply(reply)
    {:noreply, state}
  end

  def handle_cast({:queue_request, queue}, _ws, state) do
    reply =
      %Payload{
        op: @op_dispatch,
        t: "QUEUE_REQUEST",
        d: %{
          queue: queue,
        },
      }

    Logger.debug "[신경] queue: requesting"
    :gun_ws.send state.conn, reply(reply)
    {:noreply, state}
  end

  def handle_cast({:queue_ack, queue, id}, _ws, state) do
    reply =
      %Payload{
        op: @op_dispatch,
        t: "QUEUE_ACK",
        d: %{
          queue: queue,
          id: id,
        }
      }

    Logger.debug "[신경] queue: acking"
    :gun_ws.send state.conn, reply(reply)
    {:noreply, state}
  end

  def handle_cast({:metadata_update, metadata}, _ws, state) do
    reply =
      %Payload{
        op: @op_dispatch,
        t: "UPDATE_METADATA",
        d: metadata,
      }

    Logger.debug "[신경] metadata: sending update"
    :gun_ws.send state.conn, reply(reply)
    {:noreply, state}
  end

  def terminate(_info, _ws, _state) do
    Logger.info "[신경] connect: abnormal close"
    :ok
  end

  def reply(payload) do
    out =
      payload
      |> Map.from_struct
      |> Utils.stringify_keys(true)
      |> :erlang.term_to_binary

    {:binary, out}
  end

  #########################
  ## EXTERNAL SOCKET API ##
  #########################

  @doc """
  Send a message with the given payload to a single client matching the given
  routing query.
  """
  @spec send_msg(Query.t(), term()) :: :ok
  def send_msg(query, payload), do: send_msg nil, query, payload

  @doc """
  Send a message with the given payload to a single client matching the given
  routing query, sending the given nonce to allow request-response messaging.
  """
  @spec send_msg(String.t() | nil, Query.t(), term()) :: :ok
  def send_msg(nonce, query, payload) do
    GenServer.cast __MODULE__, {:send, nonce, query, payload}
  end

  @doc """
  Send a message with the given payload to all clients matching the given
  routing query.
  """
  @spec broadcast_msg(Query.t(), term()) :: :ok
  def broadcast_msg(query, payload), do: broadcast_msg nil, query, payload

  @doc """
  Send a message with the given payload to all clients matching the given
  routing query, sending the given nonce to allow request-response messaging.
  """
  @spec broadcast_msg(String.t() | nil, Query.t(), term()) :: :ok
  def broadcast_msg(nonce, query, payload) do
    GenServer.cast __MODULE__, {:broadcast, nonce, query, payload}
  end

  @doc """
  Push the specified message to the specified queue, with a routing query to
  determine what client can pull it from the queue.
  """
  @spec queue_msg(String.t(), Query.t(), term()) :: :ok
  def queue_msg(queue, query, payload), do: queue_msg queue, nil, query, payload

  @doc """
  Push the specified message to the specified queue, with a routing query to
  determine what client can pull it from the queue, sending the given nonce to
  allow request-response messaging.
  """
  @spec queue_msg(String.t(), String.t() | nil, Query.t(), term()) :: :ok
  def queue_msg(queue, nonce, query, payload) do
    GenServer.cast __MODULE__, {:queue, queue, nonce, query, payload}
  end

  @doc """
  Mark this client as being ready to process a message from the given queue.
  """
  @spec queue_request(String.t()) :: :ok
  def queue_request(queue) do
    GenServer.cast __MODULE__, {:queue_request, queue}
  end

  @doc """
  ACK a message from the given queue, letting the server know that it doesn't
  need to be requeued.
  """
  @spec queue_ack(String.t(), String.t()) :: :ok
  def queue_ack(queue, id) do
    GenServer.cast __MODULE__, {:queue_ack, queue, id}
  end

  @doc """
  Update the client's metadata. A metadata update has a few parts:

  - key
  - type
  - value

  Possible types are:

  - string
  - integer
  - float
  - version
  - list

  A metadata update looks like:

      %{
        key: %{
          type: "string",
          value: "potato",
        },
        users: %{
          type: "list",
          value: [123, 456, 789],
        }
        version: %{
          type: "version",
          value: "2.0.0",
        }
      }
  """
  @spec update_metadata(Metadata.t()) :: :ok
  def update_metadata(metadata) do
    GenServer.cast __MODULE__, {:metadata_update, metadata}
  end

  #######################
  ## REST PROXYING API ##
  #######################

  @doc """
  Proxies the given HTTP request with the given body to a target matching the
  given routing query, using the HTTP method provided.
  """
  @spec proxy(Query.t(), String.t(), http_method(), term()) :: term()
  def proxy(query, route, method, body \\ nil) do
    [{:auth, auth}] = :ets.lookup :singyeong, :auth
    [{:host, host}] = :ets.lookup :singyeong, :host
    [{:port, port}] = :ets.lookup :singyeong, :port
    [{:ssl,  ssl }] = :ets.lookup :singyeong, :ssl

    protocol = if ssl, do: "https", else: "http"

    method =
      method
      |> Atom.to_string
      |> String.upcase

    proxy_body =
      %ProxiedRequest{
        method: method,
        route: route,
        query: query,
        body: body,
      }
      |> Map.from_struct
      |> Jason.encode!

    res = HTTPoison.request! :post, "#{protocol}://#{host}:#{port}/api/v1/proxy", proxy_body,
        [{"Content-Type", "application/json"}, {"Authorization", auth}]

    res.body
  end

  ###############
  ## UTILITIES ##
  ###############

  defp id(length) do
    length
    |> :crypto.strong_rand_bytes
    |> Base.url_encode64(padding: false)
    |> binary_part(0, length)
  end
end
