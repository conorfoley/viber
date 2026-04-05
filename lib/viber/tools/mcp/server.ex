defmodule Viber.Tools.MCP.Server do
  @moduledoc """
  GenServer wrapping a single MCP server process via Port.
  """

  use GenServer

  alias Viber.Tools.MCP.Protocol

  defstruct [
    :port,
    :server_name,
    :command,
    :args,
    :env,
    :tools,
    buffer: "",
    pending: %{},
    next_id: 1
  ]

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    server_name = Keyword.fetch!(opts, :server_name)
    gen_opts = Keyword.take(opts, [:name])
    GenServer.start_link(__MODULE__, opts, gen_opts ++ [name: via(server_name)])
  end

  @spec request(pid() | GenServer.name(), String.t(), map()) ::
          {:ok, term()} | {:error, term()}
  def request(server, method, params) do
    GenServer.call(server, {:request, method, params}, 30_000)
  end

  @spec get_tools(pid() | GenServer.name()) :: [map()]
  def get_tools(server) do
    GenServer.call(server, :get_tools)
  end

  @spec set_tools(pid() | GenServer.name(), [map()]) :: :ok
  def set_tools(server, tools) do
    GenServer.call(server, {:set_tools, tools})
  end

  defp via(server_name) do
    {:via, Registry, {Viber.MCPRegistry, server_name}}
  end

  @impl true
  def init(opts) do
    server_name = Keyword.fetch!(opts, :server_name)
    command = Keyword.fetch!(opts, :command)
    args = Keyword.get(opts, :args, [])
    env = Keyword.get(opts, :env, %{})

    env_list = Enum.map(env, fn {k, v} -> {String.to_charlist(k), String.to_charlist(v)} end)

    port =
      Port.open({:spawn_executable, find_executable(command)}, [
        :binary,
        :exit_status,
        :use_stdio,
        {:args, args},
        {:env, env_list}
      ])

    state = %__MODULE__{
      port: port,
      server_name: server_name,
      command: command,
      args: args,
      env: env,
      tools: []
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:request, method, params}, from, state) do
    id = state.next_id
    data = Protocol.encode_request(id, method, params)
    Port.command(state.port, data)

    pending = Map.put(state.pending, id, from)
    {:noreply, %{state | pending: pending, next_id: id + 1}}
  end

  @impl true
  def handle_call(:get_tools, _from, state) do
    {:reply, state.tools, state}
  end

  @impl true
  def handle_call({:set_tools, tools}, _from, state) do
    {:reply, :ok, %{state | tools: tools}}
  end

  @impl true
  def handle_info({port, {:data, data}}, %{port: port} = state) do
    buffer = state.buffer <> data
    {messages, remaining} = split_messages(buffer)

    state =
      Enum.reduce(messages, %{state | buffer: remaining}, fn msg_data, acc ->
        case Protocol.decode_message(msg_data) do
          {:ok, %{type: :response, id: id} = msg} ->
            handle_response(acc, id, {:ok, msg.result})

          {:ok, %{type: :error_response, id: id} = msg} ->
            handle_response(acc, id, {:error, msg.error})

          {:ok, %{type: :notification}} ->
            acc

          _ ->
            acc
        end
      end)

    {:noreply, state}
  end

  @impl true
  def handle_info({port, {:exit_status, _status}}, %{port: port} = state) do
    for {_id, from} <- state.pending do
      GenServer.reply(from, {:error, :server_exited})
    end

    {:stop, :normal, %{state | pending: %{}}}
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    if state.port && Port.info(state.port) do
      Port.close(state.port)
    end

    :ok
  end

  defp handle_response(state, id, reply) do
    case Map.pop(state.pending, id) do
      {nil, _} ->
        state

      {from, pending} ->
        GenServer.reply(from, reply)
        %{state | pending: pending}
    end
  end

  defp split_messages(buffer) do
    lines = String.split(buffer, "\n")
    {complete, [remaining]} = Enum.split(lines, -1)
    messages = Enum.reject(complete, &(&1 == ""))
    {messages, remaining}
  end

  defp find_executable(command) do
    case System.find_executable(command) do
      nil -> command
      path -> path
    end
  end
end
