defmodule Viber.Runtime.SessionStore do
  @moduledoc """
  Ecto schema and persistence layer for conversation sessions.
  """

  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  require Logger

  alias Viber.Repo
  alias Viber.Runtime.{Session, Usage}

  @primary_key {:id, :string, autogenerate: false}

  schema "sessions" do
    field(:title, :string)
    field(:model, :string)
    field(:project_root, :string)
    field(:messages, {:array, :map}, default: [])
    field(:usage, :map, default: %{})

    timestamps()
  end

  @type t :: %__MODULE__{}

  @spec changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(session, attrs) do
    session
    |> cast(attrs, [:id, :title, :model, :project_root, :messages, :usage])
    |> validate_required([:id])
  end

  @spec available?() :: boolean()
  def available? do
    pid = Process.whereis(Viber.Repo)
    pid != nil and Process.alive?(pid)
  end

  @spec persist(String.t(), [Session.message()], Usage.t(), keyword()) ::
          {:ok, t()} | {:error, term()}
  def persist(session_id, messages, usage, opts \\ []) do
    if available?() do
      model = Keyword.get(opts, :model)
      project_root = Keyword.get(opts, :project_root)
      title = Keyword.get(opts, :title) || derive_title(messages)

      attrs = %{
        id: session_id,
        title: title,
        model: model,
        project_root: project_root,
        messages: Enum.map(messages, &encode_message/1),
        usage: encode_usage(usage)
      }

      %__MODULE__{id: session_id}
      |> changeset(attrs)
      |> Repo.insert(
        on_conflict: {:replace, [:title, :model, :project_root, :messages, :usage, :updated_at]},
        conflict_target: :id
      )
    else
      {:error, :repo_unavailable}
    end
  end

  @spec load_session(String.t()) ::
          {:ok, {[Session.message()], Usage.t(), map()}}
          | {:error, :not_found | :repo_unavailable}
  def load_session(session_id) do
    if available?() do
      case Repo.get(__MODULE__, session_id) do
        nil ->
          {:error, :not_found}

        record ->
          messages =
            record.messages
            |> Enum.map(&decode_message/1)
            |> Enum.reverse()

          usage = decode_usage(record.usage)
          meta = %{model: record.model, title: record.title, project_root: record.project_root}
          {:ok, {messages, usage, meta}}
      end
    else
      {:error, :repo_unavailable}
    end
  end

  @spec list_recent(non_neg_integer()) :: [t()]
  def list_recent(limit \\ 20) do
    if available?() do
      __MODULE__
      |> order_by([s], desc: s.updated_at)
      |> limit(^limit)
      |> Repo.all()
    else
      []
    end
  end

  @spec delete_session(String.t()) :: :ok
  def delete_session(session_id) do
    if available?() do
      __MODULE__
      |> where([s], s.id == ^session_id)
      |> Repo.delete_all()
    end

    :ok
  end

  @spec delete_older_than(non_neg_integer()) :: non_neg_integer()
  def delete_older_than(days) do
    if available?() do
      cutoff = NaiveDateTime.add(NaiveDateTime.utc_now(), -days * 86_400, :second)

      {count, _} =
        __MODULE__
        |> where([s], s.updated_at < ^cutoff)
        |> Repo.delete_all()

      count
    else
      0
    end
  end

  defp derive_title(messages) do
    user_texts =
      messages
      |> Enum.filter(fn msg -> msg.role == :user end)
      |> Enum.flat_map(fn msg ->
        Enum.flat_map(msg.blocks, fn
          {:text, text} -> [text]
          _ -> []
        end)
      end)

    substantive = Enum.find(user_texts, fn text -> String.length(String.trim(text)) > 20 end)

    case substantive || List.first(user_texts) do
      nil -> nil
      text -> String.slice(String.trim(text), 0, 100)
    end
  end

  @spec encode_message(Session.message()) :: map()
  def encode_message(msg) do
    json = %{
      "role" => Atom.to_string(msg.role),
      "blocks" => Enum.map(msg.blocks, &encode_block/1)
    }

    if msg[:usage] do
      Map.put(json, "usage", encode_usage(msg.usage))
    else
      json
    end
  end

  @spec encode_usage(Usage.t() | nil) :: map()
  def encode_usage(%Usage{} = u) do
    %{
      "input_tokens" => u.input_tokens,
      "output_tokens" => u.output_tokens,
      "cache_creation_tokens" => u.cache_creation_tokens,
      "cache_read_tokens" => u.cache_read_tokens,
      "turns" => u.turns
    }
  end

  def encode_usage(_), do: %{}

  @spec decode_message(map()) :: Session.message()
  def decode_message(json) do
    role = decode_role(json["role"])
    blocks = Enum.map(json["blocks"] || [], &decode_block/1)
    usage = if json["usage"], do: decode_usage(json["usage"]), else: nil

    %{role: role, blocks: blocks, usage: usage}
  end

  @spec decode_usage(map() | nil) :: Usage.t()
  def decode_usage(json) when is_map(json) do
    %Usage{
      input_tokens: json["input_tokens"] || 0,
      output_tokens: json["output_tokens"] || 0,
      cache_creation_tokens:
        json["cache_creation_tokens"] || json["cache_creation_input_tokens"] || 0,
      cache_read_tokens: json["cache_read_tokens"] || json["cache_read_input_tokens"] || 0,
      turns: json["turns"] || 0
    }
  end

  def decode_usage(_), do: %Usage{}

  defp encode_block({:text, text}), do: %{"type" => "text", "text" => text}

  defp encode_block({:tool_use, id, name, input}),
    do: %{"type" => "tool_use", "id" => id, "name" => name, "input" => input}

  defp encode_block({:tool_result, tool_use_id, tool_name, output, is_error}),
    do: %{
      "type" => "tool_result",
      "tool_use_id" => tool_use_id,
      "tool_name" => tool_name,
      "output" => output,
      "is_error" => is_error
    }

  defp decode_role("system"), do: :system
  defp decode_role("user"), do: :user
  defp decode_role("assistant"), do: :assistant
  defp decode_role("tool"), do: :tool

  defp decode_block(%{"type" => "text", "text" => text}), do: {:text, text}

  defp decode_block(%{"type" => "tool_use", "id" => id, "name" => name, "input" => input}),
    do: {:tool_use, id, name, input}

  defp decode_block(%{
         "type" => "tool_result",
         "tool_use_id" => tool_use_id,
         "tool_name" => tool_name,
         "output" => output,
         "is_error" => is_error
       }),
       do: {:tool_result, tool_use_id, tool_name, output, is_error}
end
