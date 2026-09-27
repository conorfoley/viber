defmodule Viber.Commands.Handlers.ModelTest do
  use ExUnit.Case, async: true

  alias Viber.Commands.Handlers.Model
  alias Viber.Runtime.Config

  defp tags_response(names) do
    fn _url, _opts ->
      {:ok, %{status: 200, body: %{"models" => Enum.map(names, &%{"name" => &1})}}}
    end
  end

  test "picker_choices lists installed Ollama models first, then hosted models" do
    {choices, {:ok, _}} =
      Model.picker_choices(%{model: "sonnet", config: nil},
        request_fun: tags_response(["qwen2.5:7b", "llama3.2:latest"])
      )

    values = Enum.map(choices, &elem(&1, 1))

    assert Enum.take(values, 2) == ["ollama:qwen2.5:7b", "ollama:llama3.2:latest"]
    assert "claude-sonnet-5" in values
    refute "ollama:mistral" in values

    {label, _} = Enum.find(choices, fn {_l, v} -> v == "claude-sonnet-5" end)
    assert label =~ "(sonnet)"
    assert label =~ "current"
  end

  test "picker_choices falls back to hosted models when Ollama is unreachable" do
    {choices, {:error, :econnrefused}} =
      Model.picker_choices(%{model: "opus", config: %Config{}},
        request_fun: fn _url, _opts -> {:error, :econnrefused} end
      )

    values = Enum.map(choices, &elem(&1, 1))
    assert "claude-opus-5" in values
    refute Enum.any?(values, &String.starts_with?(&1, "ollama:"))
  end

  test "picker_choices queries the configured Ollama base URL" do
    parent = self()

    Model.picker_choices(
      %{
        model: "ollama:qwen",
        config: %Config{provider: "ollama", base_url: "http://box:11434/v1"}
      },
      request_fun: fn url, _opts ->
        send(parent, {:url, url})
        {:ok, %{status: 200, body: %{"models" => []}}}
      end
    )

    assert_received {:url, "http://box:11434/api/tags"}
  end
end
