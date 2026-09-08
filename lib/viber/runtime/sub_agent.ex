defmodule Viber.Runtime.SubAgent do
  @moduledoc """
  Runs an isolated conversation turn as a child agent and returns the final text response.

  Sub-agents inherit model, config, project_root, permission_mode, and provider from the
  parent context but start with a fresh session (no conversation history).

  Two roles are supported:

    * `"worker"` (default) — executes the given task.
    * `"reviewer"` — independently verifies completed work. The reviewer is
      instructed to gather its own evidence (re-run tests, read files) rather
      than trust the worker's summary, and to end with a `VERDICT: passed` or
      `VERDICT: failed` line that may contradict the worker's claims.

  An optional `"effort"` (low | medium | high | xhigh | max) tunes the
  sub-agent's reasoning depth; use `"low"` for cheap scouting subtasks.
  """

  require Logger

  alias Viber.Runtime.{Conversation, Session}
  alias Viber.Runtime.Conversation.Context

  @type result :: %{
          text: String.t(),
          iterations: non_neg_integer()
        }

  @reviewer_preamble """
  You are an independent reviewer. Another agent claims to have completed the
  work described below. Your job is to deliver a verdict on whether the work
  actually succeeded:
  - Gather your own evidence: read the relevant files, run the tests, check
    diagnostics. Do not trust the worker's summary or claimed results.
  - Judge against the stated goal or proof, not against effort expended.
  - Your verdict may contradict the worker's claims; say so plainly if it does.
  - End your response with a final line of exactly "VERDICT: passed" or
    "VERDICT: failed", preceded by a short justification citing the evidence
    you inspected.
  """

  @spec run(map(), Context.t()) :: {:ok, result()} | {:error, term()}
  def run(%{"task" => task} = input, %Context{} = parent_ctx) do
    model = Map.get(input, "model", parent_ctx.model)
    extra_context = Map.get(input, "context", "")
    role = Map.get(input, "role", "worker")
    effort = Map.get(input, "effort")

    user_input =
      if extra_context != "" do
        "<context>\n#{extra_context}\n</context>\n\n#{task}"
      else
        task
      end

    user_input =
      if role == "reviewer" do
        "#{@reviewer_preamble}\n<work_to_review>\n#{user_input}\n</work_to_review>"
      else
        user_input
      end

    sub_agent_id = generate_id()

    Logger.info(
      "SubAgent: spawning id=#{sub_agent_id} role=#{role} task=#{String.slice(task, 0..80)}"
    )

    {:ok, session} =
      Session.start_link(
        model: model,
        project_root: parent_ctx.project_root
      )

    event_handler = build_event_handler(parent_ctx.event_handler, sub_agent_id)

    result =
      try do
        Conversation.run(
          session: session,
          model: model,
          config: parent_ctx.config,
          event_handler: event_handler,
          permission_mode: parent_ctx.permission_mode,
          project_root: parent_ctx.project_root,
          provider_module: parent_ctx.provider_module,
          effort: effort,
          user_input: user_input
        )
      after
        GenServer.stop(session, :normal, 5_000)
      end

    case result do
      {:ok, %{text: text, iterations: iterations}} ->
        Logger.info(
          "SubAgent: complete iterations=#{iterations} output_len=#{String.length(text)}"
        )

        {:ok, %{text: text, iterations: iterations}}

      {:error, reason} ->
        Logger.warning("SubAgent: failed reason=#{inspect(reason)}")
        {:error, reason}
    end
  end

  defp generate_id do
    :crypto.strong_rand_bytes(4) |> Base.url_encode64(padding: false)
  end

  defp build_event_handler(parent_handler, sub_agent_id) do
    fn event ->
      case event do
        %{type: type}
        when type in [:tool_use_start, :tool_result, :text_delta, :thinking_delta, :error] ->
          tagged = %{event | payload: Map.put(event.payload, :sub_agent_id, sub_agent_id)}
          parent_handler.(tagged)

        %{type: :permission_request} ->
          parent_handler.(event)

        _ ->
          :ok
      end
    end
  end
end
