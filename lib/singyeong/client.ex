defmodule Singyeong.Client do
  alias Singyeong.{
    Payload,
    Utils,
  }
  require Logger

  @behaviour :websocket_client

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


  def start_link({_app_id, _password, host, port, scheme} = opts) do
    uri = "#{scheme}://#{host}:#{port}/gateway/websocket?encoding=etf"
    Logger.debug "[신경] client: starting link, uri=#{uri}."
    :websocket_client.start_link uri, __MODULE__, opts
  end

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  @impl :websocket_client
  def init({app_id, password, host, port, scheme}) do
    :ets.new :singyeong, [:named_table, :set, :public, read_concurrency: true]
    :ets.insert :singyeong, {:app_id,   app_id}
    :ets.insert :singyeong, {:password, password}
    :ets.insert :singyeong, {:host,     host}
    :ets.insert :singyeong, {:port,     port}
    :ets.insert :singyeong, {:scheme,   scheme}

    state =
      %{
        app_id: app_id,
        client_id: id(32),
        auth: password,
      }

    Logger.debug "[신경] client: init: ready for payloads."

    {:reconnect, state}
  end

  @impl :websocket_client
  def onconnect(_ws, state) do
    Logger.info "[신경] connect: ws connected."
    {:ok, state}
  end

  @impl :websocket_client
  def ondisconnect(_ws, state) do
    # Reconnect after 100ms
    Logger.info "[신경] disconnected: reconnect in 100ms."
    {:reconnect, 100, state}
  end

  @impl :websocket_client
  def websocket_handle({:binary, msg}, _ws, state) do
    # TODO: This is unsafe
    payload = :erlang.binary_to_term msg
    try do
      case process_frame(payload[:op], payload, state) do
        {:reply, reply, new_state} ->
          out =
            reply
            |> Map.from_struct
            |> Utils.stringify_keys(true)
            |> :erlang.term_to_binary

          {:reply, {:binary, out}, new_state}

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

    {:reply, reply, state}
  end

  defp process_frame(@op_ready, _, state) do
    Logger.info "[신경] connect: ready."
    Logger.info "[신경] connect: welcome to 신경."
    {:noreply, state}
  end

  defp process_frame(@op_heartbeat_ack, _frame, state) do
    # Logger.debug "[신경] heartbeat: ack"
    {:noreply, state}
  end

  defp process_frame(@op_dispatch, frame, state) do
    # TODO: Do something with frame.t here.
    # Logger.debug "[신경] dispatch: frame: #{inspect frame}"
    payload = frame.d["payload"]
    Singyeong.Producer.notify payload
    {:noreply, state}
  end

  defp process_frame(op, frame, state) do
    Logger.warn "[신경] payload: unknown op: #{op}"
    Logger.warn "[신경] payload: suspect frame: #{inspect frame, pretty: true}"

    {:ok, state}
  end

  @impl :websocket_client
  def websocket_info({:heartbeat, interval}, _ws, %{client_id: client_id} = state) do
    reply =
      %Payload{
        op: @op_heartbeat,
        d: %{
          client_id: client_id,
        }
      }

    Process.send_after self(), {:heartbeat, interval}, interval

    {:reply, reply, state}
  end

  @impl :websocket_client
  def websocket_info({:send, nonce, query, payload}, state) do
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
    {:reply, reply, state}
  end

  @impl :websocket_client
  def websocket_info({:broadcast, nonce, query, payload}, state) do
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
    {:reply, reply, state}
  end

  @impl :websocket_client
  def websocket_info({:queue, queue, nonce, query, payload}, state) do
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
    {:reply, reply, state}
  end

  @impl :websocket_client
  def websocket_info({:queue_request, queue}, state) do
    reply =
      %Payload{
        op: @op_dispatch,
        t: "QUEUE_REQUEST",
        d: %{
          queue: queue,
        },
      }
    {:reply, reply, state}
  end

  @impl :websocket_client
  def websocket_info({:queue_ack, queue, id}, state) do
    reply =
      %Payload{
        op: @op_dispatch,
        t: "QUEUE_ACK",
        d: %{
          queue: queue,
          id: id,
        }
      }

    {:reply, reply, state}
  end

  @impl :websocket_client
  def websocket_terminate(_info, _ws, _state) do
    Logger.info "[신경] connect: abnormal close"
    :ok
  end

  #########################
  ## EXTERNAL SOCKET API ##
  #########################

  def send_msg(query, payload), do: send_msg nil, query, payload

  def send_msg(nonce, query, payload) do
    :websocket_client.cast __MODULE__, {:send, nonce, query, payload}
  end

  def broadcast_msg(query, payload), do: broadcast_msg nil, query, payload

  def broadcast_msg(nonce, query, payload) do
    :websocket_client.cast __MODULE__, {:broadcast, nonce, query, payload}
  end

  def queue_msg(queue, query, payload), do: queue_msg queue, nil, query, payload

  def queue_msg(queue, nonce, query, payload) do
    :websocket_client.cast __MODULE__, {:queue, queue, nonce, query, payload}
  end

  def queue_request(queue) do
    :websocket_client.cast __MODULE__, {:queue_request, queue}
  end

  def queue_ack(queue, id) do
    :websocket_client.cast __MODULE__, {:queue_ack, queue, id}
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
