defmodule Viber.Tools.Registry do
  @moduledoc """
  Registry of built-in tool specifications with lookup and listing.
  """

  alias Viber.Tools.Spec

  @specs %{
    "bash" => %Spec{
      name: "bash",
      description: "Execute a shell command in the current workspace.",
      input_schema: %{
        "type" => "object",
        "properties" => %{
          "command" => %{"type" => "string"},
          "timeout" => %{"type" => "integer", "minimum" => 1},
          "description" => %{"type" => "string"}
        },
        "required" => ["command"],
        "additionalProperties" => false
      },
      permission: :danger_full_access
    },
    "read_file" => %Spec{
      name: "read_file",
      description: "Read a text file from the workspace.",
      input_schema: %{
        "type" => "object",
        "properties" => %{
          "path" => %{"type" => "string"},
          "offset" => %{"type" => "integer", "minimum" => 0},
          "limit" => %{"type" => "integer", "minimum" => 1}
        },
        "required" => ["path"],
        "additionalProperties" => false
      },
      permission: :read_only
    },
    "write_file" => %Spec{
      name: "write_file",
      description: "Write a text file in the workspace.",
      input_schema: %{
        "type" => "object",
        "properties" => %{
          "path" => %{"type" => "string"},
          "content" => %{"type" => "string"}
        },
        "required" => ["path", "content"],
        "additionalProperties" => false
      },
      permission: :workspace_write
    },
    "edit_file" => %Spec{
      name: "edit_file",
      description: "Replace text in a workspace file.",
      input_schema: %{
        "type" => "object",
        "properties" => %{
          "path" => %{"type" => "string"},
          "old_string" => %{"type" => "string"},
          "new_string" => %{"type" => "string"},
          "replace_all" => %{"type" => "boolean"}
        },
        "required" => ["path", "old_string", "new_string"],
        "additionalProperties" => false
      },
      permission: :workspace_write
    },
    "glob_search" => %Spec{
      name: "glob_search",
      description: "Find files by glob pattern.",
      input_schema: %{
        "type" => "object",
        "properties" => %{
          "pattern" => %{"type" => "string"},
          "path" => %{"type" => "string"}
        },
        "required" => ["pattern"],
        "additionalProperties" => false
      },
      permission: :read_only
    },
    "grep_search" => %Spec{
      name: "grep_search",
      description: "Search file contents with a regex pattern.",
      input_schema: %{
        "type" => "object",
        "properties" => %{
          "pattern" => %{"type" => "string"},
          "path" => %{"type" => "string"},
          "glob" => %{"type" => "string"},
          "output_mode" => %{"type" => "string"},
          "-B" => %{"type" => "integer", "minimum" => 0},
          "-A" => %{"type" => "integer", "minimum" => 0},
          "-C" => %{"type" => "integer", "minimum" => 0},
          "-n" => %{"type" => "boolean"},
          "-i" => %{"type" => "boolean"},
          "type" => %{"type" => "string"},
          "head_limit" => %{"type" => "integer", "minimum" => 1},
          "offset" => %{"type" => "integer", "minimum" => 0},
          "multiline" => %{"type" => "boolean"}
        },
        "required" => ["pattern"],
        "additionalProperties" => false
      },
      permission: :read_only
    },
    "ls" => %Spec{
      name: "ls",
      description: "List files and directories at a given path.",
      input_schema: %{
        "type" => "object",
        "properties" => %{
          "path" => %{"type" => "string"},
          "depth" => %{"type" => "integer", "minimum" => 1},
          "ignore" => %{"type" => "array", "items" => %{"type" => "string"}}
        },
        "required" => ["path"],
        "additionalProperties" => false
      },
      permission: :read_only
    },
    "web_fetch" => %Spec{
      name: "web_fetch",
      description: "Fetch a URL and convert it into readable text.",
      input_schema: %{
        "type" => "object",
        "properties" => %{
          "url" => %{"type" => "string", "format" => "uri"}
        },
        "required" => ["url"],
        "additionalProperties" => false
      },
      permission: :read_only
    }
  }

  @ets_table :viber_mcp_tools

  @spec init_mcp_table() :: :ok
  def init_mcp_table do
    if :ets.whereis(@ets_table) == :undefined do
      :ets.new(@ets_table, [:named_table, :set, :public])
    end

    :ok
  end

  @spec builtin_specs() :: [Spec.t()]
  def builtin_specs, do: Map.values(@specs)

  @spec all_specs() :: [Spec.t()]
  def all_specs, do: builtin_specs() ++ mcp_specs()

  @spec get(String.t()) :: {:ok, Spec.t()} | :error
  def get(name) do
    normalized = normalize_name(name)

    case Map.fetch(@specs, normalized) do
      {:ok, _} = result ->
        result

      :error ->
        case mcp_get(normalized) do
          nil -> :error
          spec -> {:ok, spec}
        end
    end
  end

  @spec list_names() :: [String.t()]
  def list_names do
    builtin = Map.keys(@specs)
    mcp = Enum.map(mcp_specs(), & &1.name)
    Enum.sort(builtin ++ mcp)
  end

  @spec register_mcp_tools(String.t(), [Spec.t()]) :: :ok
  def register_mcp_tools(server_name, specs) do
    init_mcp_table()

    Enum.each(specs, fn spec ->
      :ets.insert(@ets_table, {{server_name, spec.name}, spec})
    end)

    :ok
  end

  @spec unregister_mcp_tools(String.t()) :: :ok
  def unregister_mcp_tools(server_name) do
    if :ets.whereis(@ets_table) != :undefined do
      :ets.match_delete(@ets_table, {{server_name, :_}, :_})
    end

    :ok
  end

  @spec mcp_specs() :: [Spec.t()]
  def mcp_specs do
    if :ets.whereis(@ets_table) != :undefined do
      :ets.tab2list(@ets_table) |> Enum.map(fn {_key, spec} -> spec end)
    else
      []
    end
  end

  @spec normalize_name(String.t()) :: String.t()
  def normalize_name(name) do
    name
    |> String.trim()
    |> String.downcase()
    |> String.replace("-", "_")
  end

  defp mcp_get(name) do
    if :ets.whereis(@ets_table) != :undefined do
      case :ets.match_object(@ets_table, {{:_, name}, :_}) do
        [{_key, spec} | _] -> spec
        [] -> nil
      end
    else
      nil
    end
  end
end
