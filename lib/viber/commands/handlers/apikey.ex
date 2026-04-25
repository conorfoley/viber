defmodule Viber.Commands.Handlers.Apikey do
  @moduledoc """
  Handler for the /apikey command.
  """

  use Viber.Commands.Handler

  alias Viber.Commands.Result
  alias Viber.Runtime.Config

  @impl Viber.Commands.Handler
  def run(_session, [], opts) do
    config = opts[:config] || %Config{}

    message =
      case config.api_key do
        nil -> "API key: (not set)"
        "" -> "API key: (not set)"
        key -> "API key: #{mask(key)}"
      end

    {:ok, Result.text(message)}
  end

  def run(_session, [key | _], _opts) when byte_size(key) == 0 do
    {:error, "API key cannot be empty"}
  end

  def run(_session, [key | _], _opts) do
    {text, patch} =
      case Config.set_user_api_key(key) do
        :ok ->
          {"API key updated and saved to user config", %{api_key: key}}

        {:error, reason} ->
          {"API key updated (could not save to user config: #{inspect(reason)})", %{api_key: key}}
      end

    {:ok, %Result{text: text, state_patch: patch}}
  end

  defp mask(key) when byte_size(key) <= 8, do: String.duplicate("*", byte_size(key))

  defp mask(key) do
    visible = String.slice(key, 0, 4)
    "#{visible}#{String.duplicate("*", byte_size(key) - 4)}"
  end
end
