defmodule Viber.Database.ConnectionManager do
  @moduledoc """
  Manages multiple database connections (Postgres and MySQL) with dynamic repo startup.
  """

  use GenServer

  require Logger

  @type db_type :: :postgres | :mysql
  @type connection_config :: %{
          name: String.t(),
          type: db_type(),
          hostname: String.t(),
          port: non_neg_integer(),
          username: String.t(),
          password: String.t(),
          database: String.t(),
          read_only: boolean(),
          pool_size: non_neg_integer()
        }

  @type state :: %{
          connections: %{String.t() => connection_config()},
          repos: %{String.t() => module()},
          active: String.t() | nil,
          active_by_session: %{String.t() => String.t()}
        }

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec add_connection(connection_config()) :: :ok | {:error, String.t()}
  def add_connection(config) do
    GenServer.call(__MODULE__, {:add_connection, config})
  end

  @spec remove_connection(String.t()) :: :ok | {:error, String.t()}
  def remove_connection(name) do
    GenServer.call(__MODULE__, {:remove_connection, name})
  end

  @spec connect(String.t()) :: {:ok, module()} | {:error, String.t()}
  def connect(name) do
    GenServer.call(__MODULE__, {:connect, name}, 30_000)
  end

  @spec set_active(String.t()) :: :ok | {:error, String.t()}
  def set_active(name) do
    GenServer.call(__MODULE__, {:set_active, name, nil})
  end

  @spec set_active(String.t(), String.t()) :: :ok | {:error, String.t()}
  def set_active(name, session_id) do
    GenServer.call(__MODULE__, {:set_active, name, session_id})
  end

  @spec get_active() :: {:ok, String.t(), module()} | {:error, String.t()}
  def get_active do
    GenServer.call(__MODULE__, {:get_active, nil})
  end

  @spec get_active(String.t()) :: {:ok, String.t(), module()} | {:error, String.t()}
  def get_active(session_id) do
    GenServer.call(__MODULE__, {:get_active, session_id})
  end

  @spec get_repo(String.t()) :: {:ok, module()} | {:error, String.t()}
  def get_repo(name) do
    GenServer.call(__MODULE__, {:get_repo, name})
  end

  @spec list_connections() :: [connection_config()]
  def list_connections do
    GenServer.call(__MODULE__, :list_connections)
  end

  @spec get_connection(String.t()) :: {:ok, connection_config()} | {:error, String.t()}
  def get_connection(name) do
    GenServer.call(__MODULE__, {:get_connection, name})
  end

  @spec is_read_only?(String.t()) :: boolean()
  def is_read_only?(name) do
    case get_connection(name) do
      {:ok, config} -> config.read_only
      _ -> true
    end
  end

  @spec add_connection_from_url(String.t(), String.t()) :: :ok | {:error, String.t()}
  def add_connection_from_url(name, url) do
    case parse_connection_url(url) do
      {:ok, config} -> add_connection(Map.put(config, :name, name))
      {:error, reason} -> {:error, reason}
    end
  end

  @spec test_connection(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def test_connection(name) do
    GenServer.call(__MODULE__, {:test_connection, name}, 15_000)
  end

  @impl true
  def init(_opts) do
    send(self(), :load_config_file)
    {:ok, %{connections: %{}, repos: %{}, active: nil, active_by_session: %{}}}
  end

  @impl true
  def handle_call({:add_connection, config}, _from, state) do
    name = config.name
    config = Map.put_new(config, :read_only, false)
    config = Map.put_new(config, :pool_size, 5)
    config = Map.put_new(config, :port, default_port(config.type))
    {:reply, :ok, put_in(state, [:connections, name], config)}
  end

  def handle_call({:remove_connection, name}, _from, state) do
    case Map.fetch(state.repos, name) do
      {:ok, repo} -> repo.stop()
      :error -> :ok
    end

    repos = Map.delete(state.repos, name)
    conns = Map.delete(state.connections, name)
    active = if state.active == name, do: nil, else: state.active
    {:reply, :ok, %{state | connections: conns, repos: repos, active: active}}
  end

  def handle_call({:connect, name}, _from, state) do
    case Map.fetch(state.connections, name) do
      {:ok, config} ->
        case start_repo(name, config) do
          {:ok, repo} ->
            repos = Map.put(state.repos, name, repo)
            active = state.active || name
            {:reply, {:ok, repo}, %{state | repos: repos, active: active}}

          {:error, reason} ->
            {:reply, {:error, "Failed to connect '#{name}': #{inspect(reason)}"}, state}
        end

      :error ->
        {:reply, {:error, "Unknown connection: #{name}"}, state}
    end
  end

  def handle_call({:set_active, name, nil}, _from, state) do
    if Map.has_key?(state.repos, name) do
      {:reply, :ok, %{state | active: name}}
    else
      {:reply, {:error, "Connection '#{name}' is not connected"}, state}
    end
  end

  def handle_call({:set_active, name, session_id}, _from, state) do
    if Map.has_key?(state.repos, name) do
      by_session = Map.put(state.active_by_session, session_id, name)
      {:reply, :ok, %{state | active_by_session: by_session}}
    else
      {:reply, {:error, "Connection '#{name}' is not connected"}, state}
    end
  end

  def handle_call({:get_active, session_id}, _from, state) do
    name =
      if session_id do
        Map.get(state.active_by_session, session_id, state.active)
      else
        state.active
      end

    case name do
      nil ->
        {:reply, {:error, "No active database connection"}, state}

      name ->
        case Map.fetch(state.repos, name) do
          {:ok, repo} -> {:reply, {:ok, name, repo}, state}
          :error -> {:reply, {:error, "Active connection '#{name}' has no running repo"}, state}
        end
    end
  end

  def handle_call({:get_repo, name}, _from, state) do
    case Map.fetch(state.repos, name) do
      {:ok, repo} -> {:reply, {:ok, repo}, state}
      :error -> {:reply, {:error, "Connection '#{name}' is not connected"}, state}
    end
  end

  def handle_call(:list_connections, _from, state) do
    conns =
      Enum.map(state.connections, fn {name, config} ->
        Map.put(config, :connected, Map.has_key?(state.repos, name))
      end)

    {:reply, conns, state}
  end

  def handle_call({:get_connection, name}, _from, state) do
    case Map.fetch(state.connections, name) do
      {:ok, config} -> {:reply, {:ok, config}, state}
      :error -> {:reply, {:error, "Unknown connection: #{name}"}, state}
    end
  end

  def handle_call({:test_connection, name}, _from, state) do
    {:reply, do_test_connection(name, state), state}
  end

  @impl true
  def handle_info(:load_config_file, state) do
    state = load_databases_config(state)
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp do_test_connection(name, state) do
    with {:ok, _config} <-
           Map.fetch(state.connections, name) |> wrap_fetch("Unknown connection: #{name}"),
         {:ok, repo} <-
           Map.fetch(state.repos, name)
           |> wrap_fetch("Connection '#{name}' is not connected. Use /connect #{name} first.") do
      ping_repo(repo, name)
    end
  end

  defp wrap_fetch({:ok, val}, _msg), do: {:ok, val}
  defp wrap_fetch(:error, msg), do: {:error, msg}

  defp ping_repo(repo, name) do
    case Ecto.Adapters.SQL.query(repo, "SELECT 1", [], timeout: 5_000) do
      {:ok, _} -> {:ok, "Connection '#{name}' is healthy"}
      {:error, reason} -> {:error, "Connection test failed: #{inspect(reason)}"}
    end
  rescue
    e -> {:error, "Connection test failed: #{Exception.message(e)}"}
  end

  defp load_databases_config(state) do
    path = config_file_path()

    if File.exists?(path) do
      try do
        {configs, _} = Code.eval_file(path)

        Enum.reduce(List.wrap(configs), state, fn config, acc ->
          config = normalize_config(config)
          name = config.name
          acc = put_in(acc, [:connections, name], config)
          Logger.info("Loaded database config: #{name}")
          acc
        end)
      rescue
        e ->
          Logger.warning("Failed to load #{path}: #{Exception.message(e)}")
          state
      end
    else
      state
    end
  end

  defp normalize_config(config) when is_map(config) do
    type = config[:type] || config["type"] || infer_type(config)

    %{
      name: config[:name] || config["name"],
      type: type,
      hostname: config[:hostname] || config["hostname"] || "localhost",
      port: config[:port] || config["port"] || default_port(type),
      username: config[:username] || config["username"] || "",
      password: config[:password] || config["password"] || "",
      database: config[:database] || config["database"] || "",
      read_only: config[:read_only] || config["read_only"] || false,
      pool_size: config[:pool_size] || config["pool_size"] || 5
    }
  end

  defp infer_type(config) do
    port = config[:port] || config["port"]
    if port == 3306, do: :mysql, else: :postgres
  end

  defp config_file_path do
    Path.join([System.user_home!(), ".viber", "databases.exs"])
  end

  @spec parse_connection_url(String.t()) :: {:ok, map()} | {:error, String.t()}
  def parse_connection_url(url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host, port: port, userinfo: userinfo, path: path}
      when scheme in ["mysql", "postgres", "postgresql"] and not is_nil(host) ->
        type = if scheme == "mysql", do: :mysql, else: :postgres
        {username, password} = parse_userinfo(userinfo)
        database = if path, do: String.trim_leading(path, "/"), else: ""

        {:ok,
         %{
           type: type,
           hostname: host,
           port: port || default_port(type),
           username: username,
           password: password,
           database: database,
           read_only: false,
           pool_size: 5
         }}

      _ ->
        {:error,
         "Invalid connection URL. Expected: mysql://user:pass@host:port/database or postgres://..."}
    end
  end

  defp parse_userinfo(nil), do: {"", ""}

  defp parse_userinfo(userinfo) do
    case String.split(userinfo, ":", parts: 2) do
      [user, pass] -> {URI.decode(user), URI.decode(pass)}
      [user] -> {URI.decode(user), ""}
    end
  end

  defp start_repo(name, config) do
    repo_module = dynamic_repo_module(name)

    if not Code.ensure_loaded?(repo_module) do
      adapter = adapter_for(config.type)

      Module.create(
        repo_module,
        quote do
          use Ecto.Repo, otp_app: :viber, adapter: unquote(adapter)
        end,
        Macro.Env.location(__ENV__)
      )
    end

    repo_config = [
      hostname: config.hostname,
      port: config.port,
      username: config.username,
      password: resolve_password(config.password),
      database: config.database,
      pool_size: config.pool_size
    ]

    Application.put_env(:viber, repo_module, repo_config)

    case repo_module.start_link() do
      {:ok, _pid} -> {:ok, repo_module}
      {:error, {:already_started, _pid}} -> {:ok, repo_module}
      {:error, reason} -> {:error, reason}
    end
  end

  defp dynamic_repo_module(name) do
    safe_name =
      name
      |> String.replace(~r/[^a-zA-Z0-9_]/, "_")
      |> Macro.camelize()

    Module.concat(Viber.Database.DynamicRepos, safe_name)
  end

  defp adapter_for(:mysql), do: Ecto.Adapters.MyXQL
  defp adapter_for(:postgres), do: Ecto.Adapters.Postgres
  defp adapter_for(_), do: Ecto.Adapters.Postgres

  defp default_port(:mysql), do: 3306
  defp default_port(:postgres), do: 5432
  defp default_port(_), do: 5432

  defp resolve_password({:system, env_var}), do: System.get_env(env_var) || ""
  defp resolve_password(password) when is_binary(password), do: password
  defp resolve_password(_), do: ""
end
