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
      {:ok, data} ->
        latest = get_in(data, ["releases", Access.at(0), "version"]) || "unknown"
        docs_url = data["docs_html_url"] || data["html_url"]

        meta = data["meta"] || %{}
        description = meta["description"] || "No description"
        licenses = meta["licenses"] || []
        links = meta["links"] || %{}

        downloads = data["downloads"] || %{}
        all_downloads = downloads["all"] || 0

        lines = [
          "# #{package} v#{latest}",
          "",
          description,
          "",
          "Downloads: #{format_number(all_downloads)}",
          "Licenses: #{Enum.join(licenses, ", ")}",
          "Docs: #{docs_url}"
        ]

        lines =
          if links != %{} do
            link_lines = Enum.map(links, fn {k, v} -> "  #{k}: #{v}" end)
            lines ++ ["Links:" | link_lines]
          else
            lines
          end

        {:ok, Enum.join(lines, "\n")}

      {:error, _} = err ->
        err
    end
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
    version = version || "latest"

    path =
      if version == "latest" do
        case hex_get("/packages/#{URI.encode(package)}") do
          {:ok, data} ->
            latest = get_in(data, ["releases", Access.at(0), "version"])
            if latest, do: {:ok, latest}, else: {:error, "No releases found"}

          err ->
            err
        end
      else
        {:ok, version}
      end

    case path do
      {:ok, ver} ->
        case hex_get("/packages/#{URI.encode(package)}/releases/#{URI.encode(ver)}") do
          {:ok, data} ->
            requirements = data["requirements"] || %{}

            if requirements == %{} do
              {:ok, "#{package} v#{ver} has no dependencies"}
            else
              dep_lines =
                Enum.map(requirements, fn {name, req} ->
                  constraint = req["requirement"] || "any"
                  optional = if req["optional"], do: " (optional)", else: ""
                  "  #{name} #{constraint}#{optional}"
                end)

              {:ok, Enum.join(["Dependencies for #{package} v#{ver}:" | dep_lines], "\n")}
            end

          {:error, _} = err ->
            err
        end

      {:error, _} = err ->
        err
    end
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
