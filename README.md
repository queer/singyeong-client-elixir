# singyeong-client

A pure Elixir client for 신경.

## Installation

[Get it on Hex.](https://hex.pm/packages/singyeong)

```elixir
def deps do
  [
    {:singyeong, "~> 0.1.0"}
  ]
end
```

## Usage

1.  Add children to your application's supervisor:
    ```Elixir
    # The actual client that connects and sends/receives messages
    {Singyeong.Client, Singyeong.parse_dsn("singyeong://my_app_name:my_password@localhost:4567")},
    # Event producer
    Singyeong.Producer,
    # Your event consumer
    MyApp.Consumer,
    ```
2.  Create a consumer:
    ```Elixir
    defmodule MyApp.Consumer do
      use Singyeong.Consumer

      def start_link do
        Consumer.start_link __MODULE__
      end

      def handle_event(event) do
        IO.inspect event, pretty: true
        :ok
      end
    end
    ```
3.  That's it! Start running your application whenever you want.