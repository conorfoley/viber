defmodule Viber.Commands.Handlers.Doctor do
  @moduledoc """
  Handler for the /doctor command. Runs environment and connectivity checks.
  """

  use Viber.Commands.Handler

  @spec execute([String.t()], map()) :: {:ok, String.t()} | {:error, String.t()}
  def execute(_args, context) do
    config = context[:config]
    checks = run_checks(config)

    lines =
      Enum.map(checks, fn {label, status, detail} ->
        icon = if status == :ok, do: "✓", else: "✗"
        base = "  #{icon} #{label}"
        if detail, do: "#{base}: #{detail}", else: base
      end)

    failed = Enum.count(checks, fn {_, status, _} -> status != :ok end)

    summary =
      if failed == 0,
        do: "\nAll checks passed.",
        else: "\n#{failed} check(s) failed."

    {:ok, "Viber Doctor\n#{Enum.join(lines, "\n")}#{summary}"}
  end

  defp run_checks(config) do
    [
      check_elixir_version(),
      check_api_key(config),
      check_provider_connectivity(config),
      check_config_files(config),
      check_mcp_servers(),
      check_database_connections(),
      check_mix_project()
    ]
  end

  defp check_elixir_version do
    version = System.version()
    otp = :erlang.system_info(:otp_release) |> to_string()
    {"Elixir/OTP", :ok, "Elixir #{version}, OTP #{otp}"}
  end

  defp check_api_key(config) do
    key =
      (config && config.api_key) ||
        System.get_env("ANTHROPIC_API_KEY") ||
        System.get_env("OPENAI_API_KEY") ||
        System.get_env("OPENROUTER_API_KEY")

    if key && String.length(key) > 10 do
      {"API key", :ok, "found (#{String.slice(key, 0, 4)}***)"}
    else
      {"API key", :error, "not found — set ANTHROPIC_API_KEY or OPENAI_API_KEY"}
    end
  end

  defp check_provider_connectivity(config) do
    base_url = (config && config.base_url) || "https://api.anthropic.com"
    health_url = build_health_url(base_url)

    case Req.get(health_url, receive_timeout: 5_000, retry: false) do
      {:ok, %{status: status}} when status < 500 ->
        {"Provider connectivity (#{base_url})", :ok, "HTTP #{status}"}

      {:ok, %{status: status}} ->
        {"Provider connectivity (#{base_url})", :error, "HTTP #{status}"}

      {:error, reason} ->
        {"Provider connectivity (#{base_url})", :error, inspect(reason)}
    end
  rescue
    _ ->
      {"Provider connectivity", :error, "request failed"}
  end

  defp build_health_url(base_url) do
    uri = URI.parse(base_url)

    "#{uri.scheme}://#{uri.host}#{if uri.port && uri.port not in [80, 443], do: ":#{uri.port}", else: ""}"
  end

  defp check_config_files(config) do
    if config && config.loaded_entries != [] do
      paths = Enum.map_join(config.loaded_entries, ", ", fn {src, path} -> "#{src}:#{path}" end)
      {"Config files", :ok, paths}
    else
      {"Config files", :ok, "no project config (using defaults)"}
    end
  end

  defp check_mcp_servers do
    try do
      servers = Viber.Tools.MCP.ServerManager.list_servers()

      if servers == [] do
        {"MCP servers", :ok, "none configured"}
      else
        names = Enum.map_join(servers, ", ", fn {name, _pid} -> name end)
        {"MCP servers", :ok, names}
      end
    rescue
      _ -> {"MCP servers", :ok, "not started"}
    end
  end

  defp check_database_connections do
    try do
      conns = Viber.Database.ConnectionManager.list_connections()

      if conns == [] do
        {"Database connections", :ok, "none configured"}
      else
        names = Enum.map_join(conns, ", ", fn {name, _} -> name end)
        {"Database connections", :ok, names}
      end
    rescue
      _ -> {"Database connections", :ok, "not started"}
    end
  end

  defp check_mix_project do
    mix_exs = Path.join(File.cwd!(), "mix.exs")

    if File.exists?(mix_exs) do
      app = Mix.Project.config()[:app]
      {"Mix project", :ok, "#{app} (#{mix_exs})"}
    else
      {"Mix project", :error, "mix.exs not found in #{File.cwd!()}"}
    end
  rescue
    _ ->
      cwd = File.cwd!()
      mix_exs = Path.join(cwd, "mix.exs")

      if File.exists?(mix_exs),
        do: {"Mix project", :ok, mix_exs},
        else: {"Mix project", :error, "mix.exs not found"}
  end
end
