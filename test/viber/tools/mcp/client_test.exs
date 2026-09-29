defmodule Viber.Tools.MCP.ClientTest do
  use ExUnit.Case, async: true

  alias Viber.Tools.Failure
  alias Viber.Tools.MCP.Client

  defp fake_server(reply) do
    spawn(fn ->
      receive do
        {:"$gen_call", from, {:request, _method, _params}} -> GenServer.reply(from, reply)
      end
    end)
  end

  test "success returns joined text content" do
    pid = fake_server({:ok, %{"content" => [%{"type" => "text", "text" => "hi"}]}})
    assert Client.call_tool(pid, "t", %{}) == {:ok, "hi"}
  end

  test "isError is an :error failure keeping the raw result" do
    result = %{"isError" => true, "content" => [%{"type" => "text", "text" => "bad"}]}
    pid = fake_server({:ok, result})

    assert {:error, %Failure{outcome: :error, message: "bad", reason: {:mcp_tool_error, ^result}}} =
             Client.call_tool(pid, "t", %{})
  end

  test "server exiting mid-call is :unknown" do
    pid = fake_server({:error, :server_exited})
    assert {:error, %Failure{outcome: :unknown}} = Client.call_tool(pid, "t", %{})
  end

  test "dead server is :not_sent" do
    pid = spawn(fn -> :ok end)
    ref = Process.monitor(pid)
    assert_receive {:DOWN, ^ref, _, _, _}

    assert {:error, %Failure{outcome: :not_sent}} = Client.call_tool(pid, "t", %{})
  end
end
