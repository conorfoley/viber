defmodule Viber.Tools.Builtins.WebFetch do
  @moduledoc """
  URL fetching via Req with basic HTML-to-text conversion.
  """

  @max_content_bytes 100_000

  @known_safe_hosts ~w(
    docs.python.org hexdocs.pm elixir-lang.org
    developer.mozilla.org stackoverflow.com
    github.com raw.githubusercontent.com
    en.wikipedia.org
  )

  @spec permission_for(map()) :: :read_only | :workspace_write
  def permission_for(%{"url" => url}) do
    uri = URI.parse(url)

    if uri.host in @known_safe_hosts do
      :read_only
    else
      :workspace_write
    end
  end

  def permission_for(_), do: :workspace_write

  @spec execute(map()) :: {:ok, String.t()} | {:error, String.t()}
  def execute(%{"url" => url}) do
    uri = URI.parse(url)

    if uri.scheme in ["http", "https"] do
      case Req.get(url: url, receive_timeout: 10_000) do
        {:ok, %{status: status, body: body}} when status in 200..299 ->
          content =
            body
            |> to_string()
            |> maybe_strip_html(content_type(body))
            |> truncate()

          {:ok, content}

        {:ok, %{status: status}} ->
          {:error, "HTTP #{status} fetching #{url}"}

        {:error, exception} ->
          {:error, "Failed to fetch #{url}: #{Exception.message(exception)}"}
      end
    else
      {:error, "Only http:// and https:// URLs are supported"}
    end
  end

  def execute(_), do: {:error, "Missing required parameter: url"}

  defp content_type(body) when is_binary(body) do
    if String.contains?(body, "<html") or String.contains?(body, "<HTML") or
         String.contains?(body, "<!DOCTYPE") or String.contains?(body, "<!doctype") do
      :html
    else
      :text
    end
  end

  defp content_type(_), do: :text

  defp maybe_strip_html(content, :html) do
    content
    |> String.replace(~r/<script[^>]*>.*?<\/script>/s, "")
    |> String.replace(~r/<style[^>]*>.*?<\/style>/s, "")
    |> String.replace(~r/<[^>]+>/, " ")
    |> String.replace(~r/&nbsp;/, " ")
    |> String.replace(~r/&amp;/, "&")
    |> String.replace(~r/&lt;/, "<")
    |> String.replace(~r/&gt;/, ">")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp maybe_strip_html(content, _), do: content

  defp truncate(content) when byte_size(content) > @max_content_bytes do
    binary_part(content, 0, @max_content_bytes) <> "\n... (content truncated at 100KB)"
  end

  defp truncate(content), do: content
end
