defmodule Viber.Tools.Builtins.Clipboard do
  @moduledoc """
  Read from and write to the system clipboard.

  Uses platform-specific commands: pbcopy/pbpaste on macOS,
  xclip on Linux, clip.exe/powershell on WSL/Windows.
  """

  @spec execute(map()) :: {:ok, String.t()} | {:error, String.t()}
  def execute(%{"action" => "read"}) do
    case paste_command() do
      {:ok, cmd, args} ->
        case System.cmd(cmd, args, stderr_to_stdout: true) do
          {content, 0} -> {:ok, content}
          {err, _} -> {:error, "Failed to read clipboard: #{err}"}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  def execute(%{"action" => "write", "text" => text}) do
    case copy_command() do
      {:ok, cmd, args} ->
        pipe_to_command(cmd, args, text)

      {:error, reason} ->
        {:error, reason}
    end
  end

  def execute(%{"action" => "write"}) do
    {:error, "Missing required parameter: text"}
  end

  def execute(%{"action" => action}) do
    {:error, "Unknown action '#{action}'; expected 'read' or 'write'"}
  end

  def execute(_) do
    {:error, "Missing required parameter: action ('read' or 'write')"}
  end

  defp paste_command do
    case :os.type() do
      {:unix, :darwin} -> {:ok, "pbpaste", []}
      {:unix, _} -> find_linux_paste()
      {:win32, _} -> {:ok, "powershell.exe", ["-command", "Get-Clipboard"]}
    end
  end

  defp copy_command do
    case :os.type() do
      {:unix, :darwin} -> {:ok, "pbcopy", []}
      {:unix, _} -> find_linux_copy()
      {:win32, _} -> {:ok, "clip.exe", []}
    end
  end

  defp find_linux_paste do
    cond do
      System.find_executable("xclip") ->
        {:ok, "xclip", ["-selection", "clipboard", "-o"]}

      System.find_executable("xsel") ->
        {:ok, "xsel", ["--clipboard", "--output"]}

      System.find_executable("wl-paste") ->
        {:ok, "wl-paste", []}

      System.find_executable("powershell.exe") ->
        {:ok, "powershell.exe", ["-command", "Get-Clipboard"]}

      true ->
        {:error, "No clipboard utility found (install xclip, xsel, or wl-clipboard)"}
    end
  end

  defp find_linux_copy do
    cond do
      System.find_executable("xclip") ->
        {:ok, "xclip", ["-selection", "clipboard"]}

      System.find_executable("xsel") ->
        {:ok, "xsel", ["--clipboard", "--input"]}

      System.find_executable("wl-copy") ->
        {:ok, "wl-copy", []}

      System.find_executable("clip.exe") ->
        {:ok, "clip.exe", []}

      true ->
        {:error, "No clipboard utility found (install xclip, xsel, or wl-clipboard)"}
    end
  end

  defp pipe_to_command(cmd, args, text) do
    tmpfile = Path.join(System.tmp_dir!(), "viber_clip_#{System.unique_integer([:positive])}")

    try do
      File.write!(tmpfile, text)

      {result, exit_code} =
        case :os.type() do
          {:win32, _} ->
            System.cmd("cmd.exe", ["/c", "type #{tmpfile} | #{cmd}"], stderr_to_stdout: true)

          _ ->
            shell_cmd = "#{cmd} #{Enum.join(args, " ")} < '#{tmpfile}'"
            System.cmd("sh", ["-c", shell_cmd], stderr_to_stdout: true)
        end

      if exit_code == 0 do
        {:ok, "Copied #{byte_size(text)} bytes to clipboard"}
      else
        {:error, "Clipboard write failed (exit #{exit_code}): #{result}"}
      end
    after
      File.rm(tmpfile)
    end
  end
end
