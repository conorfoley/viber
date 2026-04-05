defmodule Viber.Runtime.Session do
  @moduledoc """
  GenServer managing conversation history and persistence.
  """

  use GenServer

  alias Viber.Runtime.Usage

  @type message_role :: :user | :assistant | :system | :tool
  @type content_block ::
          {:text, String.t()}
          | {:tool_use, String.t(), String.t(), String.t()}
          | {:tool_result, String.t(), String.t(), String.t(), boolean()}

  @type message :: %{
          role: message_role(),
          blocks: [content_block()],
          usage: Usage.t() | nil
        }

  @type t :: %__MODULE__{
          id: String.t(),
          version: pos_integer(),
          messages: [message()],
          cumulative_usage: Usage.t(),
          storage_path: String.t() | nil
        }

  @enforce_keys [:id]
  defstruct id: nil,
            version: 1,
            messages: [],
            cumulative_usage: %Usage{},
            storage_path: nil

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    id = Keyword.get(opts, :id, generate_id())
    storage_path = Keyword.get(opts, :storage_path)
    name = Keyword.get(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, {id, storage_path}, gen_opts)
  end

  @spec add_message(GenServer.server(), message()) :: :ok
  def add_message(server, message) do
    GenServer.call(server, {:add_message, message})
  end

  @spec get_messages(GenServer.server()) :: [message()]
  def get_messages(server) do
    GenServer.call(server, :get_messages)
  end

  @spec get_usage(GenServer.server()) :: Usage.t()
  def get_usage(server) do
    GenServer.call(server, :get_usage)
  end

  @spec clear(GenServer.server()) :: :ok
  def clear(server) do
    GenServer.call(server, :clear)
  end

  @spec replace_messages(GenServer.server(), [message()]) :: :ok
  def replace_messages(server, messages) do
    GenServer.call(server, {:replace_messages, messages})
  end

  @spec save(GenServer.server()) :: {:ok, String.t()} | {:error, term()}
  def save(server) do
    GenServer.call(server, :save)
  end

  @spec load(String.t()) :: {:ok, t()} | {:error, term()}
  def load(path) do
    with {:ok, content} <- File.read(path),
         {:ok, data} <- Jason.decode(content) do
      {:ok, from_json(data, path)}
    end
  end

  @impl true
  def init({id, storage_path}) do
    state = %__MODULE__{id: id, storage_path: storage_path}
    {:ok, state}
  end

  @impl true
  def handle_call({:add_message, message}, _from, state) do
    new_usage =
      if message[:usage] do
        Usage.add(state.cumulative_usage, message.usage)
      else
        state.cumulative_usage
      end

    state = %{state | messages: state.messages ++ [message], cumulative_usage: new_usage}
    {:reply, :ok, state}
  end

  def handle_call(:get_messages, _from, state) do
    {:reply, state.messages, state}
  end

  def handle_call(:get_usage, _from, state) do
    {:reply, state.cumulative_usage, state}
  end

  def handle_call(:clear, _from, state) do
    {:reply, :ok, %{state | messages: [], cumulative_usage: %Usage{}}}
  end

  def handle_call({:replace_messages, messages}, _from, state) do
    usage = recompute_usage(messages)
    {:reply, :ok, %{state | messages: messages, cumulative_usage: usage}}
  end

  def handle_call(:save, _from, %{storage_path: nil} = state) do
    {:reply, {:error, :no_storage_path}, state}
  end

  def handle_call(:save, _from, state) do
    json = to_json(state)

    case write_json(state.storage_path, json) do
      :ok -> {:reply, {:ok, state.storage_path}, state}
      {:error, _} = err -> {:reply, err, state}
    end
  end

  defp generate_id do
    Integer.to_string(System.unique_integer([:monotonic, :positive]))
  end

  defp recompute_usage(messages) do
    Enum.reduce(messages, %Usage{}, fn msg, acc ->
      if msg[:usage], do: Usage.add(acc, msg.usage), else: acc
    end)
  end

  defp to_json(%__MODULE__{} = state) do
    %{
      "version" => state.version,
      "messages" => Enum.map(state.messages, &message_to_json/1)
    }
  end

  defp message_to_json(msg) do
    json = %{
      "role" => Atom.to_string(msg.role),
      "blocks" => Enum.map(msg.blocks, &block_to_json/1)
    }

    if msg[:usage] do
      Map.put(json, "usage", usage_to_json(msg.usage))
    else
      json
    end
  end

  defp block_to_json({:text, text}) do
    %{"type" => "text", "text" => text}
  end

  defp block_to_json({:tool_use, id, name, input}) do
    %{"type" => "tool_use", "id" => id, "name" => name, "input" => input}
  end

  defp block_to_json({:tool_result, tool_use_id, tool_name, output, is_error}) do
    %{
      "type" => "tool_result",
      "tool_use_id" => tool_use_id,
      "tool_name" => tool_name,
      "output" => output,
      "is_error" => is_error
    }
  end

  defp usage_to_json(%Usage{} = u) do
    %{
      "input_tokens" => u.input_tokens,
      "output_tokens" => u.output_tokens,
      "cache_creation_input_tokens" => u.cache_creation_tokens,
      "cache_read_input_tokens" => u.cache_read_tokens
    }
  end

  @spec from_json(map(), String.t() | nil) :: t()
  defp from_json(data, path) do
    messages = Enum.map(data["messages"] || [], &message_from_json/1)

    %__MODULE__{
      id: generate_id(),
      version: data["version"] || 1,
      messages: messages,
      cumulative_usage: recompute_usage(messages),
      storage_path: path
    }
  end

  defp message_from_json(json) do
    role = role_from_string(json["role"])
    blocks = Enum.map(json["blocks"] || [], &block_from_json/1)
    usage = if json["usage"], do: usage_from_json(json["usage"]), else: nil

    %{role: role, blocks: blocks, usage: usage}
  end

  defp role_from_string("system"), do: :system
  defp role_from_string("user"), do: :user
  defp role_from_string("assistant"), do: :assistant
  defp role_from_string("tool"), do: :tool

  defp block_from_json(%{"type" => "text", "text" => text}) do
    {:text, text}
  end

  defp block_from_json(%{"type" => "tool_use", "id" => id, "name" => name, "input" => input}) do
    {:tool_use, id, name, input}
  end

  defp block_from_json(%{
         "type" => "tool_result",
         "tool_use_id" => tool_use_id,
         "tool_name" => tool_name,
         "output" => output,
         "is_error" => is_error
       }) do
    {:tool_result, tool_use_id, tool_name, output, is_error}
  end

  defp usage_from_json(json) do
    %Usage{
      input_tokens: json["input_tokens"] || 0,
      output_tokens: json["output_tokens"] || 0,
      cache_creation_tokens: json["cache_creation_input_tokens"] || 0,
      cache_read_tokens: json["cache_read_input_tokens"] || 0,
      turns: 1
    }
  end

  defp write_json(path, data) do
    dir = Path.dirname(path)

    with :ok <- File.mkdir_p(dir),
         {:ok, encoded} <- Jason.encode(data, pretty: true) do
      File.write(path, encoded)
    end
  end
end
