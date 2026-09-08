<script lang="ts">
  import { onMount, onDestroy } from "svelte";
  import { get } from "svelte/store";
  import MessageList from "./components/MessageList.svelte";
  import InputBar from "./components/InputBar.svelte";
  import ActionStatus from "./components/ActionStatus.svelte";
  import {
    messages,
    status,
    currentAction,
    sessionUsage,
    sessionModel,
    addUserMessage,
    startAssistantMessage,
    appendDelta,
    appendAction,
    appendThinking,
    appendToolUse,
    setMessages,
  } from "./stores/conversation";
  import type { Message, SessionSummary, UserMessageResponse, UsageInfo } from "../../lib/shared";

  type ListSessionsResponse = {
    ok: boolean;
    sessions?: SessionSummary[];
    error?: string;
  };

  type SelectSessionResponse = {
    ok: boolean;
    sessionId?: string;
    messages?: Message[];
    error?: string;
  };

  let assistantMsgId = "";
  let sessionsOpen = false;
  let sessionsLoading = false;
  let sessionsError = "";
  let recentSessions: SessionSummary[] = [];
  let currentSessionId: string | null = null;
  let pendingPermission: { requestId: string; tool: string; input: string } | null = null;
  let syncing = true;
  let activeToolCount = 0;

  function ensureAssistantMsg(): void {
    if (!assistantMsgId) {
      assistantMsgId = startAssistantMessage();
    }
  }

  function handleBackground(msg: Record<string, unknown>) {
    switch (msg.type) {
      case "STREAM_START":
        status.set("thinking");
        if (!assistantMsgId) {
          assistantMsgId = startAssistantMessage();
        }
        break;

      case "STREAM_DELTA":
        ensureAssistantMsg();
        appendDelta(assistantMsgId, msg.text as string);
        break;

      case "THINKING_DELTA":
        ensureAssistantMsg();
        appendThinking(assistantMsgId, msg.text as string);
        break;

      case "TOOL_USE_START":
        ensureAssistantMsg();
        activeToolCount++;
        status.set("acting");
        currentAction.set(msg.toolName as string);
        appendToolUse(assistantMsgId, msg.toolName as string, msg.toolId as string, false);
        break;

      case "TOOL_RESULT":
        ensureAssistantMsg();
        activeToolCount = Math.max(0, activeToolCount - 1);
        appendToolUse(
          assistantMsgId,
          msg.toolName as string,
          msg.toolId as string,
          true,
          msg.isError as boolean
        );
        if (activeToolCount === 0) {
          status.set("thinking");
          currentAction.set(null);
        }
        break;

      case "BROWSER_ACTION_START":
        ensureAssistantMsg();
        status.set("acting");
        currentAction.set(msg.toolName as string);
        appendAction(assistantMsgId, msg.toolName as string, false);
        break;

      case "BROWSER_ACTION_DONE":
        status.set("thinking");
        currentAction.set(null);
        appendAction(
          assistantMsgId,
          msg.toolName as string,
          true,
          (msg.result as { is_error: boolean })?.is_error ?? false
        );
        break;

      case "TURN_COMPLETE":
        if (msg.usage) {
          sessionUsage.set(msg.usage as UsageInfo);
        }
        status.set("idle");
        currentAction.set(null);
        pendingPermission = null;
        assistantMsgId = "";
        activeToolCount = 0;
        break;

      case "INTERRUPTED":
        status.set("idle");
        currentAction.set(null);
        pendingPermission = null;
        assistantMsgId = "";
        activeToolCount = 0;
        break;

      case "PERMISSION_REQUEST":
        pendingPermission = {
          requestId: msg.requestId as string,
          tool: msg.tool as string,
          input: msg.input as string,
        };
        status.set("acting");
        break;

      case "ERROR":
        ensureAssistantMsg();
        appendDelta(assistantMsgId, `\n\n⚠ ${msg.message as string}`);
        assistantMsgId = "";
        status.set("idle");
        currentAction.set(null);
        pendingPermission = null;
        activeToolCount = 0;
        break;
    }
  }

  onMount(() => {
    const listener = (msg: unknown) => {
      handleBackground(msg as Record<string, unknown>);
    };
    browser.runtime.onMessage.addListener(listener);

    browser.runtime.sendMessage({ type: "POPUP_OPENED" }).then(async (response) => {
      const res = response as {
        ok: boolean;
        streaming: boolean;
        missedMessages: Record<string, unknown>[];
        bufferOverflowed: boolean;
      };

      const missed = res.missedMessages ?? [];
      const forceFullSync = res.bufferOverflowed;

      try {
        const syncRes = await browser.runtime.sendMessage({ type: "SYNC_MESSAGES" }) as {
          ok: boolean;
          messages?: Message[];
          sessionId?: string | null;
          model?: string | null;
          usage?: UsageInfo | null;
        };
        if (syncRes.ok && syncRes.messages) {
          if (!res.streaming || forceFullSync) {
            setMessages(syncRes.messages);
          }
          currentSessionId = syncRes.sessionId ?? null;
          if (syncRes.model) sessionModel.set(syncRes.model);
          if (syncRes.usage) sessionUsage.set(syncRes.usage);
        }
      } catch {
        currentSessionId = null;
      } finally {
        syncing = false;
      }

      if (res.streaming) {
        status.set("thinking");

        if (!forceFullSync) {
          const hasStart = missed.some((m) => m.type === "STREAM_START");
          if (!hasStart) {
            const existing = [...get(messages)].reverse().find((m) => m.role === "assistant");
            assistantMsgId = existing?.id ?? "";
          }
          for (const msg of missed) {
            handleBackground(msg);
          }
        } else {
          const existing = [...get(messages)].reverse().find((m) => m.role === "assistant");
          assistantMsgId = existing?.id ?? "";
        }
      }
    }).catch(() => { syncing = false; });

    return () => browser.runtime.onMessage.removeListener(listener);
  });

  onDestroy(() => {
    browser.runtime.sendMessage({ type: "POPUP_CLOSED" }).catch(() => {});
  });

  async function newSession(): Promise<void> {
    if ($status !== "idle") return;

    try {
      const response = await browser.runtime.sendMessage({ type: "NEW_SESSION" }) as { ok: boolean; sessionId?: string; error?: string };
      if (!response.ok) {
        throw new Error(response.error ?? "Failed to create session");
      }
      setMessages([]);
      currentSessionId = response.sessionId ?? null;
      assistantMsgId = "";
      sessionsOpen = false;
      status.set("idle");
      currentAction.set(null);
      sessionUsage.set(null);
      sessionModel.set(null);
    } catch (error) {
      console.error("Failed to create new session:", error);
    }
  }

  async function toggleSessions(): Promise<void> {
    sessionsOpen = !sessionsOpen;
    if (sessionsOpen) {
      await loadSessions();
    }
  }

  async function loadSessions(): Promise<void> {
    sessionsLoading = true;
    sessionsError = "";

    try {
      const response = await browser.runtime.sendMessage({ type: "LIST_SESSIONS" }) as ListSessionsResponse;
      if (!response.ok) {
        throw new Error(response.error ?? "Failed to load sessions");
      }
      recentSessions = response.sessions ?? [];
    } catch (error) {
      recentSessions = [];
      sessionsError = String(error);
    } finally {
      sessionsLoading = false;
    }
  }

  async function selectSession(session: SessionSummary): Promise<void> {
    if ($status !== "idle") return;

    sessionsLoading = true;
    sessionsError = "";

    try {
      const response = await browser.runtime.sendMessage({
        type: "SELECT_SESSION",
        sessionId: session.id,
      }) as SelectSessionResponse;

      if (!response.ok || !response.sessionId) {
        throw new Error(response.error ?? "Failed to resume session");
      }

      setMessages(response.messages ?? []);
      currentSessionId = response.sessionId;
      assistantMsgId = "";
      sessionsOpen = false;
      status.set("idle");
      currentAction.set(null);
      sessionUsage.set(null);
      sessionModel.set(null);

      browser.runtime.sendMessage({ type: "SYNC_MESSAGES" }).then((syncRes) => {
        const res = syncRes as { ok: boolean; model?: string | null; usage?: UsageInfo | null };
        if (res.ok) {
          if (res.model) sessionModel.set(res.model);
          if (res.usage) sessionUsage.set(res.usage);
        }
      }).catch(() => {});
    } catch (error) {
      sessionsError = String(error);
    } finally {
      sessionsLoading = false;
    }
  }

  async function respondPermission(decision: "allow" | "deny" | "always_allow"): Promise<void> {
    if (!pendingPermission) return;
    const { requestId } = pendingPermission;
    pendingPermission = null;
    status.set("thinking");

    browser.runtime.sendMessage({
      type: "PERMISSION_RESPONSE",
      requestId,
      decision,
    }).catch((error) => {
      ensureAssistantMsg();
      appendDelta(assistantMsgId, `\n\n⚠ ${String(error)}`);
      assistantMsgId = "";
      status.set("idle");
    });
  }

  async function handleSend(event: CustomEvent<string>) {
    const text = event.detail;
    addUserMessage(text);
    status.set("thinking");

    const ctx: Record<string, unknown> = await new Promise((resolve) => {
      browser.runtime.sendMessage({ type: "CAPTURE_CONTEXT" }).then((response) => {
        resolve((response as Record<string, unknown>) ?? {});
      }).catch(() => resolve({}));
    });

    browser.runtime.sendMessage({
      type: "USER_MESSAGE",
      text,
      browserContext: ctx,
    }).then((response) => {
      const result = response as UserMessageResponse;
      if (result.ok && result.sessionId) {
        currentSessionId = result.sessionId;
      } else if (!result.ok) {
        ensureAssistantMsg();
        appendDelta(assistantMsgId, `\n\n⚠ ${result.error ?? "Failed to send message"}`);
        assistantMsgId = "";
        status.set("idle");
      }
    }).catch((error) => {
      ensureAssistantMsg();
      appendDelta(assistantMsgId, `\n\n⚠ ${String(error)}`);
      assistantMsgId = "";
      status.set("idle");
    });
  }

  function sessionTitle(session: SessionSummary): string {
    return (session.title || "(untitled)").slice(0, 60);
  }

  function sessionMeta(session: SessionSummary): string {
    const model = session.model || "?";
    return `${model}, ${formatAgo(session.last_activity, session.status)}`;
  }

  function formatAgo(value: string | null | undefined, sessionStatus: string): string {
    if (!value) return sessionStatus === "active" ? "active" : "unknown";

    const date = new Date(value.endsWith("Z") ? value : `${value}Z`);
    const diff = Math.max(0, Math.floor((Date.now() - date.getTime()) / 1000));

    if (diff < 60) return "just now";
    if (diff < 3600) return `${Math.floor(diff / 60)}m ago`;
    if (diff < 86400) return `${Math.floor(diff / 3600)}h ago`;
    return `${Math.floor(diff / 86400)}d ago`;
  }

  function formatTokens(n: number): string {
    if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(1)}M`;
    if (n >= 1_000) return `${(n / 1_000).toFixed(1)}k`;
    return String(n);
  }
</script>

<main>
  <header>
    <div class="brand">
      <span class="logo">⚡ Viber</span>
      {#if currentSessionId}
        <span class="session-label">[{currentSessionId}]</span>
      {/if}
    </div>
    <div class="header-actions">
      <button class="new-session-btn" on:click={newSession} disabled={$status !== "idle"} title="New session">
        +
      </button>
      <button class="sessions-toggle" class:active={sessionsOpen} on:click={toggleSessions} disabled={$status !== "idle"}>
        Sessions
      </button>
      <ActionStatus status={$status} action={$currentAction} />
    </div>
  </header>

  {#if sessionsOpen}
    <section class="sessions-panel" aria-label="Recent sessions">
      <div class="sessions-heading">Recent sessions</div>

      {#if sessionsLoading}
        <div class="sessions-empty">Loading sessions…</div>
      {:else if sessionsError}
        <div class="sessions-error">{sessionsError}</div>
      {:else if recentSessions.length === 0}
        <div class="sessions-empty">No previous sessions found.</div>
      {:else}
        <div class="sessions-list">
          {#each recentSessions as session, index (session.id)}
            <button
              class="session-row"
              class:current={session.id === currentSessionId}
              on:click={() => selectSession(session)}
              disabled={$status !== "idle" || sessionsLoading}
            >
              <span class="session-index">{index + 1}.</span>
              <span class="session-main">
                <span class="session-title">[{session.id}] {sessionTitle(session)}</span>
                <span class="session-meta">{sessionMeta(session)}</span>
              </span>
            </button>
          {/each}
        </div>
      {/if}
    </section>
  {/if}

  <MessageList messages={$messages} />

  {#if pendingPermission}
    <section class="permission-prompt" aria-label="Permission request">
      <div class="permission-tool">{pendingPermission.tool}</div>
      <pre class="permission-input">{pendingPermission.input}</pre>
      <div class="permission-actions">
        <button class="perm-btn perm-deny" on:click={() => respondPermission("deny")}>Deny</button>
        <button class="perm-btn perm-allow" on:click={() => respondPermission("allow")}>Allow</button>
        <button class="perm-btn perm-always" on:click={() => respondPermission("always_allow")}>Always</button>
      </div>
    </section>
  {/if}

  {#if $sessionModel || $sessionUsage}
    <div class="info-bar">
      {#if $sessionModel}
        <span class="info-model">{$sessionModel}</span>
      {/if}
      {#if $sessionUsage}
        <span class="info-tokens" title="Input: {$sessionUsage.input_tokens.toLocaleString()} | Output: {$sessionUsage.output_tokens.toLocaleString()} | Cache read: {$sessionUsage.cache_read_tokens.toLocaleString()} | Cache write: {$sessionUsage.cache_creation_tokens.toLocaleString()}">
          {formatTokens($sessionUsage.total_tokens)} tokens
        </span>
        <span class="info-turns">{$sessionUsage.turns} {$sessionUsage.turns === 1 ? "turn" : "turns"}</span>
      {/if}
    </div>
  {/if}

  <InputBar disabled={$status !== "idle" || syncing} on:send={handleSend} />
</main>

<style>
  :global(*) {
    box-sizing: border-box;
    margin: 0;
    padding: 0;
  }

  :global(body) {
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    font-size: 13px;
    background: #0f0f0f;
    color: #e8e8e8;
  }

  main {
    display: flex;
    flex-direction: column;
    width: 380px;
    height: 560px;
    overflow: hidden;
  }

  header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 10px;
    padding: 10px 14px;
    background: #1a1a1a;
    border-bottom: 1px solid #2a2a2a;
    flex-shrink: 0;
  }

  .brand {
    display: flex;
    flex-direction: column;
    gap: 2px;
    min-width: 0;
  }

  .logo {
    font-weight: 700;
    font-size: 14px;
    letter-spacing: 0.02em;
    color: #fff;
  }

  .session-label {
    color: #777;
    font-size: 10px;
    max-width: 145px;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .header-actions {
    display: flex;
    align-items: center;
    gap: 8px;
    flex-shrink: 0;
  }

  .new-session-btn {
    background: #111;
    border: 1px solid #333;
    border-radius: 7px;
    color: #cfcfcf;
    cursor: pointer;
    font-family: inherit;
    font-size: 15px;
    font-weight: 700;
    line-height: 1;
    padding: 4px 8px;
    transition: background 0.15s, border-color 0.15s, color 0.15s;
  }

  .new-session-btn:hover:not(:disabled) {
    background: #202020;
    border-color: #555;
    color: #fff;
  }

  .new-session-btn:disabled {
    cursor: not-allowed;
    opacity: 0.45;
  }

  .sessions-toggle {
    background: #111;
    border: 1px solid #333;
    border-radius: 7px;
    color: #cfcfcf;
    cursor: pointer;
    font-family: inherit;
    font-size: 12px;
    padding: 5px 9px;
    transition: background 0.15s, border-color 0.15s, color 0.15s;
  }

  .sessions-toggle:hover:not(:disabled),
  .sessions-toggle.active {
    background: #202020;
    border-color: #555;
    color: #fff;
  }

  .sessions-toggle:disabled {
    cursor: not-allowed;
    opacity: 0.45;
  }

  .sessions-panel {
    flex-shrink: 0;
    background: #141414;
    border-bottom: 1px solid #2a2a2a;
    padding: 10px 14px 12px;
  }

  .sessions-heading {
    color: #aaa;
    font-size: 11px;
    font-weight: 700;
    letter-spacing: 0.04em;
    margin-bottom: 8px;
    text-transform: uppercase;
  }

  .sessions-list {
    display: flex;
    flex-direction: column;
    gap: 6px;
    max-height: 220px;
    overflow-y: auto;
  }

  .session-row {
    display: flex;
    gap: 8px;
    width: 100%;
    border: 1px solid #292929;
    border-radius: 8px;
    background: #101010;
    color: inherit;
    cursor: pointer;
    font-family: inherit;
    padding: 8px 9px;
    text-align: left;
    transition: background 0.15s, border-color 0.15s;
  }

  .session-row:hover:not(:disabled),
  .session-row.current {
    background: #1d1d1d;
    border-color: #454545;
  }

  .session-row:disabled {
    cursor: not-allowed;
    opacity: 0.55;
  }

  .session-index {
    color: #777;
    flex-shrink: 0;
    font-variant-numeric: tabular-nums;
  }

  .session-main {
    display: flex;
    flex: 1;
    flex-direction: column;
    gap: 3px;
    min-width: 0;
  }

  .session-title {
    color: #eee;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .session-meta {
    color: #777;
    font-size: 11px;
  }

  .sessions-empty,
  .sessions-error {
    color: #777;
    padding: 8px 0;
  }

  .sessions-error {
    color: #d47a7a;
  }

  .permission-prompt {
    flex-shrink: 0;
    background: #1a1a1a;
    border-top: 1px solid #2a2a2a;
    padding: 10px 14px 12px;
  }

  .permission-tool {
    color: #e0c46c;
    font-size: 12px;
    font-weight: 600;
    margin-bottom: 6px;
  }

  .permission-input {
    background: #111;
    border: 1px solid #292929;
    border-radius: 6px;
    color: #bbb;
    font-family: "SF Mono", "Fira Code", monospace;
    font-size: 11px;
    line-height: 1.4;
    margin-bottom: 10px;
    max-height: 120px;
    overflow-y: auto;
    padding: 8px;
    white-space: pre-wrap;
    word-break: break-all;
  }

  .permission-actions {
    display: flex;
    gap: 8px;
  }

  .perm-btn {
    border: 1px solid #333;
    border-radius: 7px;
    cursor: pointer;
    flex: 1;
    font-family: inherit;
    font-size: 12px;
    font-weight: 600;
    padding: 6px 0;
    transition: background 0.15s, border-color 0.15s;
  }

  .perm-deny {
    background: #1a1111;
    border-color: #4a2a2a;
    color: #d47a7a;
  }

  .perm-deny:hover {
    background: #2a1515;
    border-color: #6a3a3a;
  }

  .perm-allow {
    background: #111a11;
    border-color: #2a4a2a;
    color: #7ad47a;
  }

  .perm-allow:hover {
    background: #152a15;
    border-color: #3a6a3a;
  }

  .perm-always {
    background: #11151a;
    border-color: #2a3a4a;
    color: #7ab4d4;
  }

  .perm-always:hover {
    background: #152030;
    border-color: #3a5a7a;
  }

  .info-bar {
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 4px 14px;
    background: #141414;
    border-top: 1px solid #222;
    font-size: 10px;
    color: #666;
    flex-shrink: 0;
  }

  .info-model {
    color: #888;
    font-weight: 600;
  }

  .info-tokens {
    cursor: help;
  }

  .info-turns {
    margin-left: auto;
  }
</style>
