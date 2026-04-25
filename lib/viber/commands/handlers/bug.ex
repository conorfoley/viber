defmodule Viber.Commands.Handlers.Bug do
  @moduledoc """
  Handler for the /bug command.
  """

  use Viber.Commands.Handler

  @spec execute([String.t()], map()) :: {:ok, String.t()} | {:error, String.t()}
  def execute(_args, context) do
    model = context[:model] || "unknown"

    {os_name, os_ver} = detect_os()

    report = """
    ## Bug Report

    **Environment:**
    - Viber version: #{Application.spec(:viber, :vsn) || "dev"}
    - Elixir: #{System.version()}
    - OTP: #{System.otp_release()}
    - OS: #{os_name} #{os_ver}
    - Model: #{model}

    **Description:**
    [Describe the issue]

    **Steps to reproduce:**
    1. [Step 1]
    2. [Step 2]

    **Expected behavior:**
    [What you expected]

    **Actual behavior:**
    [What happened]
    """

    {:ok, String.trim(report)}
  end

  defp detect_os do
    case :os.type() do
      {:unix, :darwin} -> {"macOS", os_version()}
      {:unix, :linux} -> {"Linux", os_version()}
      {:win32, _} -> {"Windows", os_version()}
      {_, name} -> {to_string(name), ""}
    end
  end

  defp os_version do
    case :os.version() do
      {major, minor, patch} -> "#{major}.#{minor}.#{patch}"
      _ -> ""
    end
  end
end
