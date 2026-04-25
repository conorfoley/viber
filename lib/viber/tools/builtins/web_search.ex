defmodule Viber.Tools.Builtins.WebSearch do
  @moduledoc """
  Web search via DuckDuckGo HTML endpoint with result extraction.
  """

  @max_results 10
  @timeout_ms 10_000

  @spec execute(map()) :: {:ok, String.t()} | {:error, String.t()}
  def execute(%{"query" => query} = input) do
    max_results = input["max_results"] || @max_results
    url = "https://html.duckduckgo.com/html/?q=#{URI.encode_www_form(query)}"

    headers = [
      {"user-agent",
       "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko)"}
    ]

    case Req.get(url: url, headers: headers, receive_timeout: @timeout_ms) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        results = parse_results(body, max_results)

        if results == [] do
          {:ok, "No results found for: #{query}"}
        else
          formatted =
            results
            |> Enum.with_index(1)
            |> Enum.map_join("\n\n", fn {%{title: title, url: url, snippet: snippet}, idx} ->
              "#{idx}. #{title}\n   #{url}\n   #{snippet}"
            end)

          {:ok, "Search results for: #{query}\n\n#{formatted}"}
        end

      {:ok, %{status: status}} ->
        {:error, "Search request failed with HTTP #{status}"}

      {:error, exception} ->
        {:error, "Search request failed: #{Exception.message(exception)}"}
    end
  end

  def execute(_), do: {:error, "Missing required parameter: query"}

  defp parse_results(body, max_results) when is_binary(body) do
    ~r/<a rel="nofollow" class="result__a" href="(?<url>[^"]+)"[^>]*>(?<title>.*?)<\/a>.*?<a class="result__snippet"[^>]*>(?<snippet>.*?)<\/a>/s
    |> Regex.scan(body, capture: :all_names)
    |> Enum.take(max_results)
    |> Enum.map(fn captures ->
      [snippet, title, url] = captures

      %{
        title: strip_html(title),
        url: decode_ddg_url(url),
        snippet: strip_html(snippet)
      }
    end)
  end

  defp decode_ddg_url(url) do
    case URI.decode_www_form(url) do
      "//duckduckgo.com/l/?uddg=" <> rest ->
        rest
        |> String.split("&", parts: 2)
        |> List.first()
        |> URI.decode_www_form()

      other ->
        other
    end
  end

  defp strip_html(text) do
    text
    |> String.replace(~r/<b>/, "")
    |> String.replace(~r/<\/b>/, "")
    |> String.replace(~r/<[^>]+>/, "")
    |> String.replace(~r/&amp;/, "&")
    |> String.replace(~r/&lt;/, "<")
    |> String.replace(~r/&gt;/, ">")
    |> String.replace(~r/&quot;/, "\"")
    |> String.replace(~r/&#x27;/, "'")
    |> String.replace(~r/&nbsp;/, " ")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end
end
