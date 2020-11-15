defmodule Singyeong.Consumer do
  use ConsumerSupervisor

  @callback handle_event(term()) :: term()

  def start_link(mod) do
    GenStage.start_link __MODULE__, mod
  end

  def init(mod) do
    ConsumerSupervisor.init [
      %{
        id: mod,
        start: {mod, :start_link, []},
        restart: :transient
      }
    ], [strategy: :one_for_one, subscribe_to: [Singyeong.Producer]]
  end

  def handle_events(_events, _from, state) do
    {:noreply, [], state}
  end

  defmacro __using__(_) do
    quote do
      @behaviour Singyeong.Consumer

      alias Singyeong.Consumer
      require Logger

      def start_link(event) do
        __MODULE__.handle_event event
      end

      def child_spec(_) do
        spec =
          %{
            id: __MODULE__,
            start: {__MODULE__, :start_link, []},
          }

        Supervisor.child_spec spec, []
      end

      def handle_event(_), do: :ok

      defoverridable handle_event: 1, child_spec: 1
    end
  end
end
