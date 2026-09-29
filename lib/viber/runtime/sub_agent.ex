defmodule Viber.Runtime.SubAgent do
  @moduledoc """
  Runs an isolated conversation turn as a child agent and returns the final text response.

  Sub-agents inherit model, config, project_root, permission_mode, and provider from the
  parent context but start with a fresh session (no conversation history).

  Two roles are supported:

    * `"worker"` (default) — executes the given task.
    * `"reviewer"` — independently verifies completed work. The reviewer is
      instructed to gather its own evidence (re-run tests, read files) rather
      than trust the worker's summary, and finishes by calling the
      `submit_verdict` tool (`verdict_signature/0`) with a verdict of
      `passed` or `failed`, a justification and the evidence inspected. The
      verdict may contradict the worker's claims. If the model never calls
      the tool, a final `VERDICT: passed|failed` line is used instead.

  Concurrent sub-agents are bounded by the `:sub_agent` pool of
  `Viber.Runtime.Admission`; when it is full `run/2` returns
  `{:error, :busy}` and the spawn is refused.

  An optional `"effort"` (low | medium | high | xhigh | max) tunes the
  sub-agent's reasoning depth; use `"low"` for cheap scouting subtasks.
  """

  require Logger

  alias Viber.Runtime.{Admission, Conversation, Session, Signature}
  alias Viber.Runtime.Conversation.Context

  @type verdict :: %{String.t() => term()}

  @type result :: %{
          required(:text) => String.t(),
          required(:iterations) => non_neg_integer(),
          optional(:verdict) => verdict() | nil
        }

  @verdict_spec "-> verdict: enum[passed,failed], justification, evidence: list[string]"

  @reviewer_preamble """
  You are an independent reviewer. Another agent claims to have completed the
  work described below. Your job is to deliver a verdict on whether the work
  actually succeeded:
  - Gather your own evidence: read the relevant files, run the tests, check
    diagnostics. Do not trust the worker's summary or claimed results.
  - Judge against the stated goal or proof, not against effort expended.
  - Your verdict may contradict the worker's claims; say so plainly if it does.
  - Finish by calling submit_verdict with verdict "passed" or "failed", a
    short justification, and the evidence you inspected (files read,
    commands run and their results).
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

    event_handler = build_event_handler(parent_ctx.event_handler, sub_agent_id)

    result =
      Admission.run(:sub_agent, fn ->
        run_child(model, parent_ctx, user_input, effort, role, event_handler)
      end)

    case result do
      {:ok, %{text: text, iterations: iterations} = run} ->
        Logger.info(
          "SubAgent: complete iterations=#{iterations} output_len=#{String.length(text)}"
        )

        {:ok, finish(role, text, iterations, Map.get(run, :submitted))}

      {:ok, :interrupted} ->
        {:error, :interrupted}

      {:error, reason} ->
        Logger.warning("SubAgent: failed reason=#{inspect(reason)}")
        {:error, reason}
    end
  end

  defp run_child(model, parent_ctx, user_input, effort, role, event_handler) do
    with {:ok, session} <- start_session(model, parent_ctx.project_root) do
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
          user_input: user_input,
          terminal_tools: terminal_tools(role),
          origin: :sub_agent,
          parent_run_id: parent_ctx.run_id
        )
      after
        GenServer.stop(session, :normal, 5_000)
      end
    end
  end

  @spec verdict_signature() :: Signature.t()
  def verdict_signature do
    Signature.new!(@verdict_spec,
      name: "verdict",
      instructions:
        "Submit your final review verdict. Call this exactly once, after gathering evidence.",
      descriptions: %{
        "verdict" => "passed if the work achieved its goal, failed otherwise",
        "justification" => "Short justification citing the evidence",
        "evidence" => "Files read, commands run and their results"
      }
    )
  end

  @spec parse_verdict_line(String.t()) :: String.t() | nil
  def parse_verdict_line(text) do
    case Regex.scan(~r/VERDICT:\s*(passed|failed)\b/i, text) do
      [] -> nil
      matches -> matches |> List.last() |> List.last() |> String.downcase()
    end
  end

  defp terminal_tools("reviewer"), do: [verdict_signature()]
  defp terminal_tools(_role), do: []

  defp finish("reviewer", text, iterations, %{"verdict" => verdict}) do
    %{text: render_verdict(text, verdict), iterations: iterations, verdict: verdict}
  end

  defp finish("reviewer", text, iterations, _submitted) do
    verdict =
      case parse_verdict_line(text) do
        nil -> nil
        value -> %{"verdict" => value, "justification" => nil, "evidence" => []}
      end

    %{text: text, iterations: iterations, verdict: verdict}
  end

  defp finish(_role, text, iterations, _submitted), do: %{text: text, iterations: iterations}

  defp render_verdict(text, verdict) do
    evidence = Enum.map_join(verdict["evidence"], "\n", &("- " <> &1))

    [text, "VERDICT: #{verdict["verdict"]}", verdict["justification"], evidence]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join("\n\n")
  end

  defp start_session(model, project_root) do
    case Session.start_link(model: model, project_root: project_root) do
      {:ok, session} -> {:ok, session}
      {:error, reason} -> {:error, {:not_started, reason}}
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
