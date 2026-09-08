defmodule Viber.Tools.Builtins.HexPackageInfo do
  @moduledoc """
  Fetch package metadata from the Hex.pm API.
  """

  @hex_api "https://hex.pm/api"
  @timeout_ms 10_000

  @spec execute(map()) :: {:ok, String.t()} | {:error, String.t()}
  def execute(%{"package" => package} = input) do
    action = input["action"] || "info"

    case action do
      "info" -> fetch_info(package)
      "versions" -> fetch_versions(package)
      "deps" -> fetch_deps(package, input["version"])
      _ -> {:error, "Unknown action: #{action}. Valid: info, versions, deps"}
    end
  end

  def execute(_), do: {:error, "Missing required parameter: package"}

  defp fetch_info(package) do
    case hex_get("/packages/#{URI.encode(package)}") do
      {:ok, data} -> {:ok, build_info(package, data)}
      {:error, _} = err -> err
    end
  end

  defp build_info(package, data) do
    releases = data["releases"] || []
    latest = get_in(releases, [Access.at(0), "version"]) || "unknown"
    docs_url = data["docs_html_url"] || data["html_url"]
    meta = data["meta"] || %{}

    base_lines(package, latest, docs_url, meta, data)
    |> append_links(meta["links"] || %{})
    |> Enum.join("\n")
  end

  defp base_lines(package, latest, docs_url, meta, data) do
    description = meta["description"] || "No description"
    licenses = meta["licenses"] || []
    downloads = data["downloads"] || %{}
    all_downloads = downloads["all"] || 0

    [
      "# #{package} v#{latest}",
      "",
      description,
      "",
      "Downloads: #{format_number(all_downloads)}",
      "Licenses: #{Enum.join(licenses, ", ")}",
      "Docs: #{docs_url}"
    ]
  end

  defp append_links(lines, links) when links == %{}, do: lines

  defp append_links(lines, links) do
    link_lines = Enum.map(links, fn {k, v} -> "  #{k}: #{v}" end)
    lines ++ ["Links:" | link_lines]
  end

  defp fetch_versions(package) do
    case hex_get("/packages/#{URI.encode(package)}") do
      {:ok, data} ->
        releases = data["releases"] || []

        version_lines =
          releases
          |> Enum.take(20)
          |> Enum.map(fn rel ->
            ver = rel["version"]
            inserted = rel["inserted_at"] || ""
            date = String.slice(inserted, 0, 10)
            "  #{ver} (#{date})"
          end)

        header =
          "Versions for #{package} (showing #{min(20, length(releases))} of #{length(releases)}):"

        {:ok, Enum.join([header | version_lines], "\n")}

      {:error, _} = err ->
        err
    end
  end

  defp fetch_deps(package, version) do
    with {:ok, ver} <- resolve_version(package, version || "latest"),
         {:ok, data} <- hex_get("/packages/#{URI.encode(package)}/releases/#{URI.encode(ver)}") do
      {:ok, build_deps(package, ver, data["requirements"] || %{})}
    end
  end

  defp resolve_version(_package, version) when version != "latest", do: {:ok, version}

  defp resolve_version(package, "latest") do
    case hex_get("/packages/#{URI.encode(package)}") do
      {:ok, data} ->
        case get_in(data, ["releases", Access.at(0), "version"]) do
          nil -> {:error, "No releases found"}
          latest -> {:ok, latest}
        end

      err ->
        err
    end
  end

  defp build_deps(package, ver, requirements) when requirements == %{},
    do: "#{package} v#{ver} has no dependencies"

  defp build_deps(package, ver, requirements) do
    dep_lines =
      Enum.map(requirements, fn {name, req} ->
        constraint = req["requirement"] || "any"
        optional = if req["optional"], do: " (optional)", else: ""
        "  #{name} #{constraint}#{optional}"
      end)

    Enum.join(["Dependencies for #{package} v#{ver}:" | dep_lines], "\n")
  end

  defp hex_get(path) do
    url = @hex_api <> path

    case Req.get(
           url: url,
           headers: [{"accept", "application/json"}],
           receive_timeout: @timeout_ms
         ) do
      {:ok, %{status: 200, body: body}} when is_map(body) ->
        {:ok, body}

      {:ok, %{status: 200, body: body}} when is_binary(body) ->
        case Jason.decode(body) do
          {:ok, data} -> {:ok, data}
          {:error, _} -> {:error, "Failed to parse Hex API response"}
        end

      {:ok, %{status: 404}} ->
        {:error, "Package not found on Hex.pm"}

      {:ok, %{status: status}} ->
        {:error, "Hex API returned HTTP #{status}"}

      {:error, exception} ->
        {:error, "Hex API request failed: #{Exception.message(exception)}"}
    end
  end

  defp format_number(n) when n >= 1_000_000, do: "#{Float.round(n / 1_000_000, 1)}M"
  defp format_number(n) when n >= 1_000, do: "#{Float.round(n / 1_000, 1)}K"
  defp format_number(n), do: to_string(n)
end
