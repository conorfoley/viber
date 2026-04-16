defmodule Viber.Runtime.Session do
  @moduledoc """
  GenServer managing conversation history and persistence.
  """

  use GenServer

  require Logger

  alias Viber.Runtime.{SessionStore, Usage}

  @type message_role :: :user | :assistant | :system | :tool
  @type content_block ::
          {:text, String.t()}
          | {:tool_use, String.t(), String.t(), String.t() | map()}
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
          storage_path: String.t() | nil,
          model: String.t() | nil,
          project_root: String.t() | nil,
          persist_timer: reference() | nil
        }

  @enforce_keys [:id]
  defstruct id: nil,
            version: 1,
            messages: [],
            cumulative_usage: %Usage{},
            storage_path: nil,
            model: nil,
            project_root: nil,
            persist_timer: nil

  @persist_delay_ms 2_000

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    id = Keyword.get(opts, :id, generate_id())
    storage_path = Keyword.get(opts, :storage_path)
    model = Keyword.get(opts, :model)
    project_root = Keyword.get(opts, :project_root)
    name = Keyword.get(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, {id, storage_path, model, project_root}, gen_opts)
  end

  @spec resume(String.t(), keyword()) :: {:ok, pid()} | {:error, term()}
  def resume(session_id, opts \\ []) do
    case SessionStore.load_session(session_id) do
      {:ok, {messages, usage, meta}} ->
        name = Keyword.get(opts, :name)
        gen_opts = if name, do: [name: name], else: []

        GenServer.start_link(
          __MODULE__,
          {:resume, session_id, messages, usage, meta},
          gen_opts
        )

      {:error, _} = err ->
        err
    end
  end

  @spec get_id(GenServer.server()) :: String.t()
  def get_id(server) do
    GenServer.call(server, :get_id)
  end

  @spec get_project_root(GenServer.server()) :: String.t() | nil
  def get_project_root(server) do
    GenServer.call(server, :get_project_root)
  end

  @spec set_model(GenServer.server(), String.t()) :: :ok
  def set_model(server, model) do
    GenServer.call(server, {:set_model, model})
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

  @spec undo_last_turn(GenServer.server()) :: {:ok, non_neg_integer()} | {:error, String.t()}
  def undo_last_turn(server) do
    GenServer.call(server, :undo_last_turn)
  end

  @spec get_last_user_message(GenServer.server()) :: {:ok, String.t()} | {:error, String.t()}
  def get_last_user_message(server) do
    GenServer.call(server, :get_last_user_message)
  end

  @spec pop_last_turn(GenServer.server()) ::
          {:ok, String.t(), non_neg_integer()} | {:error, String.t()}
  def pop_last_turn(server) do
    GenServer.call(server, :pop_last_turn)
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
  def init({id, storage_path, model, project_root}) do
    state = %__MODULE__{
      id: id,
      storage_path: storage_path,
      model: model,
      project_root: project_root
    }

    {:ok, state}
  end

  @impl true
  def init({:resume, id, messages, usage, meta}) do
    state = %__MODULE__{
      id: id,
      messages: messages,
      cumulative_usage: usage,
      model: meta[:model],
      project_root: meta[:project_root]
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:get_id, _from, state) do
    {:reply, state.id, state}
  end

  @impl true
  def handle_call(:get_project_root, _from, state) do
    {:reply, state.project_root, state}
  end

  @impl true
  def handle_call({:set_model, model}, _from, state) do
    {:reply, :ok, %{state | model: model}}
  end

  @impl true
  def handle_call({:add_message, message}, _from, state) do
    new_usage =
      if message[:usage] do
        Usage.add(state.cumulative_usage, message.usage)
      else
        state.cumulative_usage
      end

    state = %{state | messages: [message | state.messages], cumulative_usage: new_usage}
    {:reply, :ok, schedule_persist(state)}
  end

  @impl true
  def handle_call(:get_messages, _from, state) do
    {:reply, Enum.reverse(state.messages), state}
  end

  @impl true
  def handle_call(:get_usage, _from, state) do
    {:reply, state.cumulative_usage, state}
  end

  @impl true
  def handle_call(:clear, _from, state) do
    state = %{state | messages: [], cumulative_usage: %Usage{}}
    {:reply, :ok, schedule_persist(state)}
  end

  @impl true
  def handle_call({:replace_messages, messages}, _from, state) do
    usage = recompute_usage(messages)
    state = %{state | messages: Enum.reverse(messages), cumulative_usage: usage}
    {:reply, :ok, schedule_persist(state)}
  end

  @impl true
  def handle_call(:undo_last_turn, _from, state) do
    case Enum.find_index(state.messages, fn m -> m.role == :user end) do
      nil ->
        {:reply, {:error, "No user messages to undo"}, state}

      idx ->
        kept = Enum.drop(state.messages, idx + 1)
        removed = idx + 1
        usage = recompute_usage(kept)
        new_state = %{state | messages: kept, cumulative_usage: usage}
        {:reply, {:ok, removed}, schedule_persist(new_state)}
    end
  end

  @impl true
  def handle_call(:get_last_user_message, _from, state) do
    result =
      state.messages
      |> Enum.find(fn m -> m.role == :user end)
      |> case do
        nil ->
          {:error, "No user messages in history"}

        msg ->
          text =
            Enum.find_value(msg.blocks, fn
              {:text, t} -> t
              _ -> nil
            end)

          if text, do: {:ok, text}, else: {:error, "Last user message has no text content"}
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call(:pop_last_turn, _from, state) do
    case Enum.find_index(state.messages, fn m -> m.role == :user end) do
      nil ->
        {:reply, {:error, "No user messages to undo"}, state}

      idx ->
        msg = Enum.at(state.messages, idx)

        text =
          Enum.find_value(msg.blocks, fn
            {:text, t} -> t
            _ -> nil
          end)

        if text == nil do
          {:reply, {:error, "Last user message has no text content"}, state}
        else
          kept = Enum.drop(state.messages, idx + 1)
          removed = idx + 1
          usage = recompute_usage(kept)
          new_state = %{state | messages: kept, cumulative_usage: usage}
          {:reply, {:ok, text, removed}, schedule_persist(new_state)}
        end
    end
  end

  @impl true
  def handle_call(:save, _from, %{storage_path: nil} = state) do
    {:reply, {:error, :no_storage_path}, state}
  end

  @impl true
  def handle_call(:save, _from, state) do
    json = to_json(state)

    case write_json(state.storage_path, json) do
      :ok -> {:reply, {:ok, state.storage_path}, state}
      {:error, _} = err -> {:reply, err, state}
    end
  end

  @impl true
  def handle_info(:persist, state) do
    do_persist(state)
    {:noreply, %{state | persist_timer: nil}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    do_persist(state)
    :ok
  end

  defp schedule_persist(state) do
    if state.persist_timer, do: Process.cancel_timer(state.persist_timer)
    timer = Process.send_after(self(), :persist, @persist_delay_ms)
    %{state | persist_timer: timer}
  end

  defp do_persist(state) do
    messages = Enum.reverse(state.messages)

    case SessionStore.persist(state.id, messages, state.cumulative_usage,
           model: state.model,
           project_root: state.project_root
         ) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.warning("Failed to persist session #{state.id}: #{inspect(reason)}")
    end
  rescue
    e ->
      Logger.warning("Failed to persist session #{state.id}: #{Exception.message(e)}")
  end

  defp generate_id do
    :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)
  end

  defp recompute_usage(messages) do
    Enum.reduce(messages, %Usage{}, fn msg, acc ->
      if msg[:usage], do: Usage.add(acc, msg.usage), else: acc
    end)
  end

  defp to_json(%__MODULE__{} = state) do
    %{
      "id" => state.id,
      "version" => state.version,
      "messages" => state.messages |> Enum.reverse() |> Enum.map(&SessionStore.encode_message/1)
    }
  end

  @spec from_json(map(), String.t() | nil) :: t()
  defp from_json(data, path) do
    messages = Enum.map(data["messages"] || [], &SessionStore.decode_message/1)

    %__MODULE__{
      id: data["id"] || generate_id(),
      version: data["version"] || 1,
      messages: Enum.reverse(messages),
      cumulative_usage: recompute_usage(messages),
      storage_path: path
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
