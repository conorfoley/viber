defmodule Viber.Runtime.ConfigTest do
  use ExUnit.Case, async: true

  alias Viber.Runtime.Config

  @tag :tmp_dir
  test "loads from a single file", %{tmp_dir: tmp_dir} do
    viber_dir = Path.join(tmp_dir, ".viber")
    File.mkdir_p!(viber_dir)

    File.write!(
      Path.join(viber_dir, "settings.json"),
      Jason.encode!(%{"model" => "claude-sonnet-4-6", "customInstructions" => "be terse"})
    )

    {:ok, config} = Config.load(project_root: tmp_dir)
    assert config.model == "claude-sonnet-4-6"
    assert config.custom_instructions == "be terse"
  end

  @tag :tmp_dir
  test "loads provider and base_url from config file", %{tmp_dir: tmp_dir} do
    viber_dir = Path.join(tmp_dir, ".viber")
    File.mkdir_p!(viber_dir)

    File.write!(
      Path.join(viber_dir, "settings.json"),
      Jason.encode!(%{
        "model" => "llama3",
        "provider" => "ollama",
        "baseUrl" => "http://192.168.1.50:11434"
      })
    )

    {:ok, config} = Config.load(project_root: tmp_dir)
    assert config.model == "llama3"
    assert config.provider == "ollama"
    assert config.base_url == "http://192.168.1.50:11434"
  end

  @tag :tmp_dir
  test "loads api_key from config file", %{tmp_dir: tmp_dir} do
    viber_dir = Path.join(tmp_dir, ".viber")
    File.mkdir_p!(viber_dir)

    File.write!(
      Path.join(viber_dir, "settings.json"),
      Jason.encode!(%{
        "provider" => "ollama",
        "baseUrl" => "https://cloud-ollama.example.com",
        "apiKey" => "secret-token"
      })
    )

    {:ok, config} = Config.load(project_root: tmp_dir)
    assert config.provider == "ollama"
    assert config.base_url == "https://cloud-ollama.example.com"
    assert config.api_key == "secret-token"
  end

  test "merging two configs — later overrides scalar, deep-merges maps" do
    base = %Config{
      model: "claude-sonnet-4-6",
      provider: nil,
      base_url: nil,
      mcp_servers: %{"server_a" => {:stdio, %{command: "a", args: [], env: %{}}}},
      hooks: %{pre_tool_use: ["hook1"], post_tool_use: []}
    }

    override = %Config{
      model: "grok-3",
      provider: nil,
      base_url: nil,
      mcp_servers: %{"server_b" => {:http, %{url: "http://localhost", headers: %{}}}},
      hooks: %{pre_tool_use: ["hook2"], post_tool_use: []}
    }

    merged = Config.merge(base, override)
    assert merged.model == "grok-3"
    assert Map.has_key?(merged.mcp_servers, "server_a")
    assert Map.has_key?(merged.mcp_servers, "server_b")
    assert merged.hooks.pre_tool_use == ["hook1", "hook2"]
  end

  test "merging propagates provider and base_url with last-wins semantics" do
    base = %Config{
      provider: "openai",
      base_url: "https://api.openai.com/v1"
    }

    override = %Config{
      provider: "ollama",
      base_url: "http://localhost:11434"
    }

    merged = Config.merge(base, override)
    assert merged.provider == "ollama"
    assert merged.base_url == "http://localhost:11434"
  end

  test "merging keeps base provider when override is nil" do
    base = %Config{provider: "ollama", base_url: "http://localhost:11434"}
    override = %Config{model: "llama3"}

    merged = Config.merge(base, override)
    assert merged.provider == "ollama"
    assert merged.base_url == "http://localhost:11434"
    assert merged.model == "llama3"
  end

  @tag :tmp_dir
  test "MCP server config parsing — stdio and sse", %{tmp_dir: tmp_dir} do
    viber_dir = Path.join(tmp_dir, ".viber")
    File.mkdir_p!(viber_dir)

    File.write!(
      Path.join(viber_dir, "settings.json"),
      Jason.encode!(%{
        "mcpServers" => %{
          "my_server" => %{
            "command" => "node",
            "args" => ["server.js"],
            "env" => %{"PORT" => "3000"}
          },
          "remote" => %{"url" => "http://example.com/sse", "transport" => "sse"}
        }
      })
    )

    {:ok, config} = Config.load(project_root: tmp_dir)
    assert {:stdio, %{command: "node", args: ["server.js"]}} = config.mcp_servers["my_server"]
    assert {:sse, %{url: "http://example.com/sse"}} = config.mcp_servers["remote"]
  end

  @tag :tmp_dir
  test "missing file returns default config", %{tmp_dir: tmp_dir} do
    original = System.get_env("XDG_CONFIG_HOME")
    no_config_dir = Path.join(tmp_dir, "fake_config_home")
    System.put_env("XDG_CONFIG_HOME", no_config_dir)

    try do
      {:ok, config} = Config.load(project_root: tmp_dir)
      assert config.model == nil
      assert config.provider == nil
      assert config.base_url == nil
      assert config.mcp_servers == %{}
      assert config.loaded_entries == []
    after
      if original,
        do: System.put_env("XDG_CONFIG_HOME", original),
        else: System.delete_env("XDG_CONFIG_HOME")
    end
  end

  test "get/2 resolves provider and baseUrl paths" do
    config = %Config{
      model: "llama3",
      provider: "ollama",
      base_url: "http://localhost:11434"
    }

    assert Config.get(config, "model") == "llama3"
    assert Config.get(config, "provider") == "ollama"
    assert Config.get(config, "baseUrl") == "http://localhost:11434"
    assert Config.get(config, "unknown") == nil
  end
end
