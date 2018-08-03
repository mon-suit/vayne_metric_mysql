defmodule Vayne.Metric.Mysql do

  @behaviour Vayne.Task.Metric

  @moduledoc """
  Get Mysql metrics
  """

  @doc """
  Params below:

  * `hostname`: Mysql hostname.Required.
  * `port`: Mysql port. Not required, default 3306.
  * `username`: username. Not required.
  * `password`: password. Not required.
  * `role`: check role, "master" or "slave". Not required. Default "master".

  """

  @default_role "master"
  @default_params [skip_database: true]
  def init(params) do
    if Map.has_key?(params, "hostname") do
      role  = Map.get(params, "role", @default_role)
      params = Enum.reduce(~w(hostname port username password), [], fn (k, acc) ->
        if params[k] do
          Keyword.put(acc, String.to_atom(k), params[k])
        else
          acc
        end
      end)
      params = Keyword.merge(params, @default_params)
      case Mariaex.start_link(params) do
        {:ok, conn} -> {:ok, {conn, role}}
        {:error, error} -> {:error, error}
      end
    else
      {:error, "hostname is required"}
    end
  end
  
  def run({conn, role}, log_func) do
    with {:ok, global_status} <- get_global_status(conn),
         {:ok, variables} <- get_mysql_variables(conn),
         {:ok, slave_status} <- get_slave_status({conn, role})
    do
      hash = global_status |> Map.merge(variables) |> Map.merge(slave_status)

      metric_cal = %{}
      |> acc_per_second(hash)
      |> acc_connection(hash)
      |> acc_slave(hash, role, log_func)

      metric = hash
      |> Map.to_list
      |> Enum.reduce(%{}, fn ({k, v}, acc) ->
        value = try_parse(v)
        if is_number(value), do: Map.put(acc, k, value), else: acc
      end)
      |> Map.merge(metric_cal)
      |> Map.put("mysql.alive", 1)

      {:ok, metric}
    else
      {:error, error} ->
        log_func.(error)
        {:ok, %{"mysql.alive" => 0}}
    end
  end

  def acc_per_second(acc, hash) do
    com_tps = ~w(Com_commit Com_rollback)
    |> Enum.reduce(0, fn(x, acc)-> acc + String.to_integer(hash[x]) end)

    com_qps = hash["Queries"] |> try_parse

    acc
    |> Map.put("Com_qps", com_qps)
    |> Map.put("Com_tps", com_tps)
  end

  def acc_connection(acc, hash) do
    check = ~w(Threads_connected max_connections)
    |> Enum.all?(fn k -> is_binary(hash[k]) and hash[k] =~ ~r/^\d+$/ end)

    if check do
      connections = hash["Threads_connected"] |> String.to_integer
      max_conn    = hash["max_connections"]   |> String.to_integer
      percent     = Float.floor(connections * 100 / max_conn, 3)
      Map.put(acc, "ConnectionPercent", percent)
    else
      acc
    end
  end

  @mysql_slave_keys ~w(Slave_IO_Running Slave_SQL_Running)
  def acc_slave(acc, hash, "slave", log_func) do
    unless Map.has_key?(hash, hd(@mysql_slave_keys)) do
      Map.put(acc, "No_slave_status", 1)
    else
      acc = Enum.reduce(@mysql_slave_keys, acc, fn(x, acc)-> 
        value = cond do
          hash[x] == "Yes" -> 1
          true             -> 0
        end
        Map.put(acc, x, value)
      end)

      second = hash["Seconds_Behind_Master"]
      value = cond do
        is_integer(second) ->
          second
        is_binary(second) and second =~ ~r/^\d+$/ ->
          String.to_integer(second)
        true ->
          log_func.("Seconds_Behind_Master format error: #{hash["Seconds_Behind_Master"]}")
          -1
      end
      Map.put(acc, "Seconds_Behind_Master", value)
    end
  end
  def acc_slave(acc, _hash, _role, _log_func), do: acc

  @variables ~w(max_connections)
  def get_mysql_variables(conn) do
    try do
      ret = @variables
      |> Enum.reduce([], fn (var, acc) ->
        %{:rows => rows} = Mariaex.query!(conn, "show variables like '#{var}';")
        rows ++ acc
      end)
      |> parse_rows
      {:ok, ret}
    rescue
      err -> 
        {:error, "get variables failed: #{inspect err}"}
    catch
      :exit, {:timeout, err} ->
        {:error, "get variables failed: #{inspect err}"}
    end
  end

  def get_global_status(conn) do
    try do
      %{:rows => rows} = Mariaex.query!(conn, "show global status;")
      {:ok, parse_rows(rows)}
    rescue
      err -> 
        {:error, "get global status failed: #{inspect err}"}
    catch
      :exit, {:timeout, err} ->
        {:error, "get global status failed: #{inspect err}"}
    end
  end

  def get_slave_status({_conn, "master"}), do: {:ok, %{}}
  def get_slave_status({conn, "slave"}) do
    try do
      ret = case Mariaex.query!(conn, "show slave status;")  do
        %{:rows => [s_rows], :columns => s_col} ->
          Enum.zip(s_col, s_rows) |> Enum.into(%{})
        _ ->
          %{}
      end
      {:ok, ret}
    rescue
      err -> 
        {:error, "get slave status failed: #{inspect err}"}
    end
  end

  def get_slave_status({_conn, role}, _log_func) do
    {:error, "get slave status failed: unknown role #{role}"}
  end

  def parse_rows(rows), do: rows |> Enum.map(fn([k, v]) -> {k, v} end) |> Enum.into(%{})
  
  defp try_parse(value) when is_binary(value) do
    case Integer.parse(value) do
      {v, _} -> v
      _      -> value
    end
  end
  defp try_parse(value), do: value

  def clean({conn, _role}) do
    GenServer.stop(conn)
    :ok
  end

end
