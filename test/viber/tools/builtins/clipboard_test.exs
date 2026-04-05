defmodule Viber.Tools.Builtins.ClipboardTest do
  use ExUnit.Case, async: false

  alias Viber.Tools.Builtins.Clipboard

  defp macos?, do: match?({:unix, :darwin}, :os.type())

  defp save_clipboard do
    if macos?() do
      case System.cmd("pbpaste", [], stderr_to_stdout: true) do
        {content, 0} -> content
        _ -> ""
      end
    end
  end

  defp restore_clipboard(nil), do: :ok

  defp restore_clipboard(previous) do
    Clipboard.execute(%{"action" => "write", "text" => previous})
    :ok
  end

  test "read returns current clipboard contents" do
    if macos?() do
      assert {:ok, _content} = Clipboard.execute(%{"action" => "read"})
    end
  end

  test "write copies text to clipboard and read retrieves it" do
    if macos?() do
      previous = save_clipboard()

      try do
        marker = "viber_test_#{System.unique_integer([:positive])}"
        assert {:ok, msg} = Clipboard.execute(%{"action" => "write", "text" => marker})
        assert msg =~ "bytes to clipboard"

        assert {:ok, content} = Clipboard.execute(%{"action" => "read"})
        assert String.trim(content) == marker
      after
        restore_clipboard(previous)
      end
    end
  end

  test "write without text returns error" do
    assert {:error, msg} = Clipboard.execute(%{"action" => "write"})
    assert msg =~ "Missing required parameter: text"
  end

  test "unknown action returns error" do
    assert {:error, msg} = Clipboard.execute(%{"action" => "delete"})
    assert msg =~ "Unknown action"
  end

  test "missing action returns error" do
    assert {:error, msg} = Clipboard.execute(%{})
    assert msg =~ "Missing required parameter: action"
  end
end
