defmodule Session do
  use GenServer

  def wait_connect_ok(socket, remote_address, remote_port) do
    case :gen_udp.recv(socket, 0, 5000) do
      {:ok, {_, _, msg}} ->
        case Message.from_json(msg) do
          {:ok, {:connect_ok, m}} ->
            {:ok, %{socket: socket,
                    connection_id: m.connection_id,
                    remote_address: Dict.get(m, :address, remote_address),
                    remote_port: Dict.get(m, :port, remote_port)}}
          {:ok, _} -> {:stop, :no_connect_ok}
          {:error, e} -> {:stop, e}
        end
      {:error, reason} -> {:stop, reason}
    end
  end

  def init(args) do
    {:ok, socket} = :gen_udp.open(args.local_port, [:binary, active: false])
    {:ok, connect_msg} = Message.connect(args.local_address, args.local_port)
    |> Message.to_json
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
    {:ok, msg} = Message.pong(state.connection_id) |> Message.to_json
    :gen_udp.send(state.socket, state.remote_address, state.remote_port, msg)
    {:noreply, state}
  end

  def handle_cast(:stop, state) do
    {:stop, :normal, state}
  end

  def handle_info({:udp, _, _, _, msg}, state) do
    case Message.from_json(msg) do
      {:ok, {:ping}} -> GenServer.cast(self, :pong)
    end
    :inet.setopts(state.socket, [active: :once])
    {:noreply, state}
  end
end
