defmodule Singyeong.Producer do
  use GenStage
  require Logger

  def start_link(_) do
    GenStage.start_link __MODULE__, :ok, name: __MODULE__
  end

  @doc """
  Sends an event and returns only after the event is dispatched.
  """
  def sync_notify(event, timeout \\ 5000) do
    GenStage.call __MODULE__, {:notify, event}, timeout
  end

  @doc """
  Sends an event and returns immediately.
  """
  def notify(event) do
    GenStage.cast __MODULE__, {:notify, event}
  end

  def init(:ok) do
    {:producer, {:queue.new, 0}, dispatcher: GenStage.BroadcastDispatcher}
  end

  def handle_call({:notify, event}, from, {queue, demand}) do
    dispatch_events :queue.in({from, event}, queue), demand, []
  end

  def handle_cast({:notify, event}, {queue, demand}) do
    dispatch_events :queue.in({nil, event}, queue), demand, []
  end

  def handle_demand(incoming_demand, {queue, demand}) do
    dispatch_events queue, incoming_demand + demand, []
  end

  defp dispatch_events(queue, demand, events) do
    with d when d > 0 <- demand,
        {item, queue} = :queue.out(queue),
        {:value, {from, event}} <- item do
      # Cast events don't have something to respond to
      unless is_nil(from) do
        GenStage.reply from, :ok
      end
      dispatch_events queue, demand - 1, [event | events]
    else
      _ -> {:noreply, Enum.reverse(events), {queue, demand}}
    end
  end
end
