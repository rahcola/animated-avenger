defmodule Session do
  use GenServer

  defp parse_ip(s) do
    s |> String.to_char_list |> :inet.parse_address
  end

  defmodule Connect do
    defstruct [:address, :port]
    @type t :: %Connect{address: :inet.ip4_address, port: :inet.port_number}

    def parse(%{"address" => s, "port" => port}) do
      {:ok, address} = Session.parse_ip(s)
      {:ok, %Connect{address: address, port: port}}
    end
  end

  defmodule ConnectOk do
    defstruct [:connection_id, :address, :port]
    @type t :: %ConnectOk{connection_id: String.t,
                          address: :inet.ip4_address,
                          port: :inet.port_number}

    def parse(m) do
      {:ok, address} = if Dict.has_key?(m, "address") do
                         Session.parse_ip m["address"]
                       else
                         {:ok, nil}
                       end
      {:ok, %ConnectOk{connection_id: m["connection-id"],
                       address: address,
                       port: m["port"]}}
    end
  end

  defmodule Pong do
    defstruct [:connection_id]
    @type t :: %Pong{connection_id: String.t}
  end

  defimpl JSON.Encoder, for: Connect do
    def encode(%Connect{address: address, port: port}) do
      JSON.encode(%{type: "connect",
                    address: address |> :inet.ntoa |> to_string,
                    port: port})
    end

    def typeof(_) do
      :object
    end
  end

  defimpl JSON.Encoder, for: ConnectOk do
    def encode(%ConnectOk{connection_id: id, address: address, port: port}) do
      JSON.encode(%{type: "connect-ok",
                    "connection-id": id,
                    address: address |> :inet.ntoa |> to_string,
                    port: port})
    end

    def typeof(_) do
      :object
    end
  end

  defimpl JSON.Encoder, for: Pong do
    def encode(%Pong{connection_id: id}) do
      JSON.encode(%{type: "pong", "connection-id": id})
    end

    def typeof(_) do
      :object
    end
  end

  def parse_message(msg) do
    case JSON.decode(msg) do
      {:ok, m} ->
        case m do
          %{"type" => "connect"} -> Connect.parse(m)
          %{"type" => "connect-ok"} -> ConnectOk.parse(m)
          %{"type" => "ping"} -> {:ok, :ping}
          _ -> {:error, :unknow_message}
        end
      e -> e
    end
  end

  def wait_connect_ok(socket, remote_address, remote_port) do
    case :gen_udp.recv(socket, 0, 5000) do
      {:ok, {_, _, msg}} ->
        case parse_message(msg) do
          {:ok, %ConnectOk{connection_id: id,
                           address: address,
                            port: port}} ->
            {:ok, %{socket: socket,
                    connection_id: id,
                    remote_address: address || remote_address,
                    remote_port: port || remote_port}}
          {:ok, _} -> {:stop, :no_connect_ok}
          {:error, e} -> {:stop, e}
        end
      {:error, reason} -> {:stop, reason}
    end
  end

  def init(args) do
    {:ok, socket} = :gen_udp.open(args.local_port, [:binary, active: false])
    {:ok, connect_msg} = JSON.encode(%Connect{address: args.local_address,
                                              port: args.local_port})
    :gen_udp.send(socket, args.remote_address, args.remote_port, connect_msg)
    case wait_connect_ok(socket, args.remote_address, args.remote_port) do
      {:error, reason} ->
        :gen_udp.close(socket)
        {:stop, reason}
      ok ->
        :inet.setopts(socket, [active: :once])
        ok
    end
  end

  def terminate(:normal, state) do
    :gen_udp.close(state.socket)
    :ok
  end

  def handle_cast(:pong, state) do
    {:ok, msg} = JSON.encode(%Pong{connection_id: state.connection_id})
    :gen_udp.send(state.socket, state.remote_address, state.remote_port, msg)
    {:noreply, state}
  end

  def handle_cast(:stop, state) do
    {:stop, :normal, state}
  end

  def handle_info({:udp, _, _, _, msg}, state) do
    case parse_message(msg) do
      {:ok, :ping} -> GenServer.cast(self, :pong)
    end
    :inet.setopts(state.socket, [active: :once])
    {:noreply, state}
  end
end
