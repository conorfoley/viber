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

  test "merging two configs — later overrides scalar, deep-merges maps" do
    base = %Config{
      model: "claude-sonnet-4-6",
      mcp_servers: %{"server_a" => {:stdio, %{command: "a", args: [], env: %{}}}},
      hooks: %{pre_tool_use: ["hook1"], post_tool_use: []}
    }

    override = %Config{
      model: "grok-3",
      mcp_servers: %{"server_b" => {:http, %{url: "http://localhost", headers: %{}}}},
      hooks: %{pre_tool_use: ["hook2"], post_tool_use: []}
    }

    merged = Config.merge(base, override)
    assert merged.model == "grok-3"
    assert Map.has_key?(merged.mcp_servers, "server_a")
    assert Map.has_key?(merged.mcp_servers, "server_b")
    assert merged.hooks.pre_tool_use == ["hook1", "hook2"]
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
    {:ok, config} = Config.load(project_root: tmp_dir)
    assert config.model == nil
    assert config.mcp_servers == %{}
    assert config.loaded_entries == []
  end
end
