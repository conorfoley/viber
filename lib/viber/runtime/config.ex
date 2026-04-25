defmodule Viber.Runtime.Config do
  @moduledoc """
  Layered config discovery and merging from User → Project → Local.
  """

  require Logger

  @type config_source :: :user | :project | :local

  @type mcp_server_config ::
          {:stdio, %{command: String.t(), args: [String.t()], env: %{String.t() => String.t()}}}
          | {:sse, %{url: String.t(), headers: %{String.t() => String.t()}}}
          | {:http, %{url: String.t(), headers: %{String.t() => String.t()}}}

  @type hooks_config :: %{
          pre_tool_use: [String.t()],
          post_tool_use: [String.t()]
        }

  @type t :: %__MODULE__{
          model: String.t() | nil,
          provider: String.t() | nil,
          base_url: String.t() | nil,
          api_key: String.t() | nil,
          permission_mode: atom() | nil,
          max_iterations: pos_integer() | nil,
          mcp_servers: %{String.t() => mcp_server_config()},
          hooks: hooks_config(),
          custom_instructions: String.t() | nil,
          loaded_entries: [{config_source(), String.t()}]
        }

  defstruct model: nil,
            provider: nil,
            base_url: nil,
            api_key: nil,
            permission_mode: nil,
            max_iterations: nil,
            mcp_servers: %{},
            hooks: %{pre_tool_use: [], post_tool_use: []},
            custom_instructions: nil,
            loaded_entries: []

  @spec load(keyword()) :: {:ok, t()} | {:error, term()}
  def load(opts \\ []) do
    project_root = Keyword.get(opts, :project_root, File.cwd!())
    entries = discover(project_root)

    config =
      Enum.reduce(entries, %__MODULE__{}, fn {source, path}, acc ->
        case load_file(path) do
          {:ok, data} ->
            merge(acc, from_map(data, source, path))

          {:error, reason} ->
            Logger.warning("Failed to load config from #{path}: #{inspect(reason)}")
            acc
        end
      end)

    {:ok, config}
  end

  @spec merge(t(), t()) :: t()
  def merge(%__MODULE__{} = base, %__MODULE__{} = override) do
    %__MODULE__{
      model: override.model || base.model,
      provider: override.provider || base.provider,
      base_url: override.base_url || base.base_url,
      api_key: override.api_key || base.api_key,
      permission_mode: override.permission_mode || base.permission_mode,
      max_iterations: override.max_iterations || base.max_iterations,
      mcp_servers: Map.merge(base.mcp_servers, override.mcp_servers),
      hooks: %{
        pre_tool_use: base.hooks.pre_tool_use ++ override.hooks.pre_tool_use,
        post_tool_use: base.hooks.post_tool_use ++ override.hooks.post_tool_use
      },
      custom_instructions: override.custom_instructions || base.custom_instructions,
      loaded_entries: base.loaded_entries ++ override.loaded_entries
    }
  end

  @spec set_user_api_key(String.t()) :: :ok | {:error, term()}
  def set_user_api_key(api_key) when is_binary(api_key) do
    path = user_config_path()

    existing =
      case File.read(path) do
        {:ok, content} ->
          case Jason.decode(content) do
            {:ok, map} when is_map(map) -> map
            _ -> %{}
          end

        {:error, :enoent} ->
          %{}

        {:error, _} ->
          %{}
      end

    updated = Map.put(existing, "apiKey", api_key)

    with :ok <- File.mkdir_p(Path.dirname(path)),
         {:ok, encoded} <- Jason.encode(updated, pretty: true) do
      File.write(path, encoded)
    end
  end

  @spec get(t(), String.t()) :: term()
  def get(%__MODULE__{} = config, path) do
    case String.split(path, ".") do
      ["model"] -> config.model
      ["provider"] -> config.provider
      ["baseUrl"] -> config.base_url
      ["permissionMode"] -> config.permission_mode
      ["customInstructions"] -> config.custom_instructions
      ["maxIterations"] -> config.max_iterations
      ["mcpServers"] -> config.mcp_servers
      ["mcpServers", name] -> Map.get(config.mcp_servers, name)
      ["hooks"] -> config.hooks
      _ -> nil
    end
  end

  defp discover(project_root) do
    user_path = user_config_path()
    project_path = Path.join([project_root, ".viber", "settings.json"])
    local_path = Path.join([project_root, ".viber", "settings.local.json"])

    [{:user, user_path}, {:project, project_path}, {:local, local_path}]
    |> Enum.filter(fn {_source, path} -> File.exists?(path) end)
  end

  defp user_config_path do
    config_home =
      System.get_env("XDG_CONFIG_HOME") ||
        Path.join(System.user_home!(), ".config")

    Path.join([config_home, "viber", "settings.json"])
  end

  defp load_file(path) do
    case File.read(path) do
      {:ok, content} -> Jason.decode(content)
      {:error, _} = err -> err
    end
  end

  defp from_map(data, source, path) when is_map(data) do
    %__MODULE__{
      model: data["model"],
      provider: data["provider"],
      base_url: data["baseUrl"],
      api_key: data["apiKey"],
      permission_mode: parse_permission_mode(data["permissions"]),
      max_iterations: parse_max_iterations(data["maxIterations"]),
      mcp_servers: parse_mcp_servers(data["mcpServers"] || %{}),
      hooks: parse_hooks(data["hooks"] || %{}),
      custom_instructions: data["customInstructions"],
      loaded_entries: [{source, path}]
    }
  end

  defp parse_permission_mode(nil), do: nil

  defp parse_permission_mode(%{"allow" => _} = perms) do
    Viber.Runtime.Permissions.mode_from_string(perms["allow"] || "prompt")
  end

  defp parse_permission_mode(mode) when is_binary(mode) do
    Viber.Runtime.Permissions.mode_from_string(mode)
  end

  defp parse_permission_mode(_), do: nil

  defp parse_mcp_servers(servers) when is_map(servers) do
    Map.new(servers, fn {name, config} -> {name, parse_mcp_server(config)} end)
  end

  defp parse_mcp_servers(_), do: %{}

  defp parse_mcp_server(%{"command" => command} = config) do
    {:stdio,
     %{
       command: command,
       args: config["args"] || [],
       env: config["env"] || %{}
     }}
  end

  defp parse_mcp_server(%{"url" => url, "transport" => "sse"} = config) do
    {:sse, %{url: url, headers: config["headers"] || %{}}}
  end

  defp parse_mcp_server(%{"url" => url} = config) do
    {:http, %{url: url, headers: config["headers"] || %{}}}
  end

  defp parse_hooks(hooks) when is_map(hooks) do
    %{
      pre_tool_use: hooks["PreToolUse"] || [],
      post_tool_use: hooks["PostToolUse"] || []
    }
  end

  defp parse_hooks(_), do: %{pre_tool_use: [], post_tool_use: []}

  defp parse_max_iterations(val) when is_integer(val) and val > 0, do: val
  defp parse_max_iterations(_), do: nil
end
