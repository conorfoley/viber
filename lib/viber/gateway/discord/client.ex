defmodule Viber.Gateway.Discord.Client do
  @moduledoc """
  Discord REST API v10 client.

  Covers the three operations the Gateway needs:
  - Responding to deferred slash-command interactions (followup webhook)
  - Sending proactive messages to a channel (requires bot token)
  - Triggering the typing indicator in a channel
  - Registering global slash commands at startup
  """

  require Logger

  @base_url "https://discord.com/api/v10"

  @spec create_followup(String.t(), String.t(), String.t()) :: :ok | {:error, term()}
  def create_followup(application_id, interaction_token, content) do
    url = "#{@base_url}/webhooks/#{application_id}/#{interaction_token}"

    case Req.post(url, json: %{content: content}) do
      {:ok, %{status: status}} when status in 200..299 ->
        :ok

      {:ok, %{status: status, body: body}} ->
        Logger.warning("Discord followup failed status=#{status} body=#{inspect(body)}")
        {:error, {status, body}}

      {:error, reason} ->
        Logger.error("Discord followup request error: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @spec send_channel_message(String.t(), String.t(), String.t()) :: :ok | {:error, term()}
  def send_channel_message(bot_token, channel_id, content) do
    url = "#{@base_url}/channels/#{channel_id}/messages"

    case Req.post(url,
           json: %{content: content},
           headers: [{"authorization", "Bot #{bot_token}"}]
         ) do
      {:ok, %{status: status}} when status in 200..299 ->
        :ok

      {:ok, %{status: status, body: body}} ->
        Logger.warning(
          "Discord send_channel_message failed status=#{status} body=#{inspect(body)}"
        )

        {:error, {status, body}}

      {:error, reason} ->
        Logger.error("Discord send_channel_message error: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @spec trigger_typing(String.t(), String.t()) :: :ok | {:error, term()}
  def trigger_typing(bot_token, channel_id) do
    url = "#{@base_url}/channels/#{channel_id}/typing"

    case Req.post(url,
           body: "",
           headers: [{"authorization", "Bot #{bot_token}"}]
         ) do
      {:ok, %{status: 204}} ->
        :ok

      {:ok, %{status: status, body: body}} ->
        {:error, {status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec register_global_command(String.t(), String.t(), map()) :: :ok | {:error, term()}
  def register_global_command(bot_token, application_id, command) do
    url = "#{@base_url}/applications/#{application_id}/commands"

    case Req.post(url,
           json: command,
           headers: [{"authorization", "Bot #{bot_token}"}]
         ) do
      {:ok, %{status: status}} when status in 200..299 ->
        :ok

      {:ok, %{status: status, body: body}} ->
        Logger.warning(
          "Discord register_global_command failed status=#{status} body=#{inspect(body)}"
        )

        {:error, {status, body}}

      {:error, reason} ->
        Logger.error("Discord register_global_command error: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
