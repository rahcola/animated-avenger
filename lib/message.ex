defmodule Message do
  defp keys_to_atoms(m) do
    Enum.reduce(m, %{}, fn({k, v}, mm) ->
      Dict.put(mm, (String.replace(k, "-", "_") |> String.to_atom), v)
    end)
  end

  defp string_to_address(m) do
    if Dict.has_key?(m, :address) do
      Dict.update!(m, :address, fn(s) ->
        {:ok, cl} = String.to_char_list(s) |> :inet.parse_address
        cl
      end)
    else
      m
    end
  end

  def atoms_to_keys(m) do
    Enum.reduce(m, %{}, fn({k, v}, mm) ->
      Dict.put(mm, (to_string(k) |> String.replace("_", "-")), v)
    end)
  end

  defp address_to_string(m) do
    if Dict.has_key?(m, :address) do
      Dict.update!(m, :address, fn(t) -> :inet.ntoa(t) |> to_string end)
    else
      m
    end
  end

  def from_json(s) do
    case JSON.decode(s) do
      {:ok, mm} ->
        m = Dict.delete(mm, "type") |> keys_to_atoms |> string_to_address
        {:ok, case mm["type"] do
                "connect" -> {:connect, m}
                "connect-ok" -> {:connect_ok, m}
                "ping" -> {:ping}
                "pong" -> {:pong, m}
              end}
      e -> e
    end
  end

  def to_json({type, fields}) do
    m = address_to_string fields |> atoms_to_keys
    case type do
      :connect -> Dict.put(m, "type", "connect") |> JSON.encode
      :connect_ok -> Dict.put(m, "type", "connect-ok")  |> JSON.encode
      :ping -> Dict.put(m, "type", "ping") |> JSON.encode
      :pong -> Dict.put(m, "type", "pong") |> JSON.encode
      _ -> {:error, :unknown_message_type}
    end
  end

  def connect(address, port) do
    {:connect, %{address: address, port: port}}
  end

  def pong(connection_id) do
    {:pong, %{connection_id: connection_id}}
  end
end
