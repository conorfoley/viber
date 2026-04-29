import { MESSAGE_FETCH_LIMIT, SESSION_LIST_LIMIT } from "../lib/shared";
import type { Message, SessionSummary } from "../lib/shared";
import { mapServerMessages } from "../lib/messages";
import type { ServerMessage } from "../lib/messages";

const VIBER_URL = "http://localhost:4100";
const SESSION_KEY = "viber_session_id";

type SseEvent =
  | { type: "text_delta"; payload: { text: string } }
  | { type: "thinking_delta"; payload: { text: string } }
  | { type: "tool_use_start"; payload: { name: string; id: string } }
  | { type: "tool_result"; payload: { name: string; id: string; output: string; is_error: boolean } }
  | { type: "turn_complete"; payload: Record<string, unknown> }
  | { type: "error"; payload: { message: string } }
  | { type: "interrupted"; payload: { message: string } }
  | { type: "browser_action"; payload: { action_id: string; tool_name: string; input: Record<string, unknown> } }
  | { type: "permission_request"; payload: { request_id: string; tool: string; input: string } }
  | { type: string; payload: Record<string, unknown> };

async function getOrCreateSession(): Promise<string> {
  const stored = await browser.storage.local.get(SESSION_KEY);
  if (stored[SESSION_KEY]) {
    const existing = stored[SESSION_KEY] as string;
    const ok = await ensureActiveSession(existing);
    if (ok) return existing;
  }
  return createSession();
}

async function getCurrentSessionId(): Promise<string | null> {
  const stored = await browser.storage.local.get(SESSION_KEY);
  return (stored[SESSION_KEY] as string | undefined) ?? null;
}

async function fetchSessionInfo(id: string): Promise<SessionSummary | null> {
  try {
    const res = await fetch(`${VIBER_URL}/sessions/${id}`);
    if (!res.ok) return null;
    return await res.json() as SessionSummary;
  } catch {
    return null;
  }
}

async function ensureActiveSession(id: string): Promise<boolean> {
  const info = await fetchSessionInfo(id);
  if (!info) return false;
  if (info.status === "active") return true;

  try {
    const res = await fetch(`${VIBER_URL}/sessions/${id}/resume`, { method: "POST" });
    return res.ok || res.status === 409;
  } catch {
    return false;
  }
}

async function createSession(): Promise<string> {
  const res = await fetch(`${VIBER_URL}/sessions`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({}),
  });
  if (!res.ok) throw new Error(`Failed to create session: ${res.status}`);
  const data = await res.json() as { id: string };
  await browser.storage.local.set({ [SESSION_KEY]: data.id });
  return data.id;
}

async function listSessions(): Promise<SessionSummary[]> {
  const res = await fetch(`${VIBER_URL}/sessions`);
  if (!res.ok) throw new Error(`Failed to list sessions: ${res.status}`);
  const data = await res.json() as { sessions?: SessionSummary[] };
  return (data.sessions ?? []).slice(0, SESSION_LIST_LIMIT);
}

async function selectSession(id: string): Promise<{ sessionId: string; messages: Message[] }> {
  const ok = await ensureActiveSession(id);
  if (!ok) throw new Error(`Session '${id}' not found.`);
  await browser.storage.local.set({ [SESSION_KEY]: id });
  const messages = await fetchMessages(id);
  return { sessionId: id, messages };
}

async function fetchMessages(id: string): Promise<Message[]> {
  const res = await fetch(`${VIBER_URL}/sessions/${id}/messages?limit=${MESSAGE_FETCH_LIMIT}`);
  if (!res.ok) throw new Error(`Failed to load messages: ${res.status}`);
  const data = await res.json() as { messages?: ServerMessage[] };
  return mapServerMessages(data.messages ?? []);
}

async function captureContext(tabId: number): Promise<Record<string, unknown>> {
  try {
    const results = await browser.scripting.executeScript({
      target: { tabId },
      func: () => {
        return {
          tree: (window as Window & { __viber_build_a11y_tree?: (mode?: "interactive" | "full") => string })
            .__viber_build_a11y_tree?.("interactive") ?? "",
          width: window.innerWidth,
          height: window.innerHeight,
        };
      },
    });
    const data = (results[0]?.result as { tree: string; width: number; height: number } | undefined)
      ?? { tree: "", width: 0, height: 0 };
    const tab = await browser.tabs.get(tabId);
    return {
      url: tab.url ?? "",
      title: tab.title ?? "",
      accessibility_tree: data.tree,
      viewport: { width: data.width, height: data.height },
    };
  } catch {
    return {};
  }
}

async function executeActionInTab(
  tabId: number,
  toolName: string,
  input: Record<string, unknown>
): Promise<{ output: string; is_error: boolean }> {
  try {
    const results = await browser.scripting.executeScript({
      target: { tabId },
      func: (tn: string, inp: Record<string, unknown>) => {
        return (window as Window & {
          __viber_execute_action?: (
            toolName: string,
            input: Record<string, unknown>
          ) => Promise<{ output: string; is_error: boolean }>;
        }).__viber_execute_action?.(tn, inp);
      },
      args: [toolName, input],
    });
    const result = results[0]?.result;
    if (result && typeof result === "object" && "output" in result) {
      return result as { output: string; is_error: boolean };
    }
    return { output: `No result from content script for ${toolName}`, is_error: true };
  } catch (e) {
    return { output: `Content script error: ${String(e)}`, is_error: true };
  }
}

async function postActionResult(
  sessionId: string,
  actionId: string,
  result: { output: string; is_error: boolean }
): Promise<void> {
  await fetch(`${VIBER_URL}/sessions/${sessionId}/browser_action_result`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ action_id: actionId, result }),
  });
}

async function respondToPermission(
  sessionId: string,
  requestId: string,
  decision: "allow" | "deny" | "always_allow"
): Promise<void> {
  const res = await fetch(`${VIBER_URL}/sessions/${sessionId}/permissions/${requestId}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ decision }),
  });
  if (!res.ok) throw new Error(`Permission response failed: ${res.status}`);
}

let streamingState: { active: boolean; sessionId: string | null } = {
  active: false,
  sessionId: null,
};

let missedMessages: Record<string, unknown>[] = [];
let popupAlive = false;
let bufferOverflowed = false;

const MAX_BUFFERED = 500;

function bufferMessage(message: Record<string, unknown>): void {
  if (missedMessages.length < MAX_BUFFERED) {
    missedMessages.push(message);
  } else {
    bufferOverflowed = true;
  }
}

function broadcastOrBuffer(message: Record<string, unknown>): void {
  if (popupAlive) {
    browser.runtime.sendMessage(message).catch(() => {
      bufferMessage(message);
      popupAlive = false;
    });
  } else {
    bufferMessage(message);
  }
}

async function sendMessage(
  sessionId: string,
  text: string,
  browserContext: Record<string, unknown>
): Promise<void> {
  const tabs = await browser.tabs.query({ active: true, currentWindow: true });
  const tabId = tabs[0]?.id;

  let response: Response;
  try {
    response = await fetch(`${VIBER_URL}/sessions/${sessionId}/message`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        message: text,
        browser_context: browserContext,
      }),
    });
  } catch (e) {
    broadcastOrBuffer({ type: "ERROR", message: `Cannot reach Viber server: ${String(e)}` });
    return;
  }

  if (!response.ok || !response.body) {
    broadcastOrBuffer({ type: "ERROR", message: `HTTP ${response.status}` });
    return;
  }

  streamingState = { active: true, sessionId };
  broadcastOrBuffer({ type: "STREAM_START" });

  const reader = response.body.getReader();
  const decoder = new TextDecoder();
  let buffer = "";

  let receivedTerminal = false;

  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;

      buffer += decoder.decode(value, { stream: true });
      const frames = buffer.split("\n\n");
      buffer = frames.pop() ?? "";

      for (const frame of frames) {
        let eventType = "";
        const dataLines: string[] = [];

        for (const line of frame.split("\n")) {
          if (line.startsWith("event: ")) {
            eventType = line.slice(7).trim();
          } else if (line.startsWith("data: ")) {
            dataLines.push(line.slice(6));
          }
        }

        const dataLine = dataLines.join("\n").trim();
        if (eventType && dataLine) {
          try {
            const evt = JSON.parse(dataLine) as SseEvent;
            if (evt.type === "turn_complete" || evt.type === "error" || evt.type === "interrupted") {
              receivedTerminal = true;
            }
            await handleSseEvent(evt, sessionId, tabId ?? null);
          } catch {
          }
        }
      }
    }
  } catch (e) {
    broadcastOrBuffer({ type: "ERROR", message: `Stream disconnected: ${String(e)}` });
  } finally {
    if (!receivedTerminal) {
      streamingState = { active: false, sessionId: null };
      broadcastOrBuffer({ type: "TURN_COMPLETE", usage: null });
    }
  }
}

async function handleSseEvent(
  evt: SseEvent,
  sessionId: string,
  tabId: number | null
): Promise<void> {
  switch (evt.type) {
    case "text_delta":
      broadcastOrBuffer({ type: "STREAM_DELTA", text: evt.payload.text });
      break;

    case "thinking_delta":
      broadcastOrBuffer({ type: "THINKING_DELTA", text: evt.payload.text });
      break;

    case "tool_use_start": {
      const { name, id } = evt.payload as { name: string; id: string };
      broadcastOrBuffer({ type: "TOOL_USE_START", toolName: name, toolId: id });
      break;
    }

    case "tool_result": {
      const { name, id, is_error } = evt.payload as {
        name: string;
        id: string;
        is_error: boolean;
      };
      broadcastOrBuffer({ type: "TOOL_RESULT", toolName: name, toolId: id, isError: is_error });
      break;
    }

    case "turn_complete": {
      streamingState = { active: false, sessionId: null };
      const usage = (evt.payload as { usage?: Record<string, number> }).usage ?? null;
      broadcastOrBuffer({ type: "TURN_COMPLETE", usage });
      break;
    }

    case "error":
      streamingState = { active: false, sessionId: null };
      broadcastOrBuffer({ type: "ERROR", message: evt.payload.message });
      break;

    case "interrupted":
      streamingState = { active: false, sessionId: null };
      broadcastOrBuffer({ type: "INTERRUPTED" });
      break;

    case "permission_request": {
      const { request_id, tool, input } = evt.payload as {
        request_id: string;
        tool: string;
        input: string;
      };
      broadcastOrBuffer({ type: "PERMISSION_REQUEST", requestId: request_id, tool, input });
      break;
    }

    case "browser_action": {
      const { action_id, tool_name, input } = evt.payload as {
        action_id: string;
        tool_name: string;
        input: Record<string, unknown>;
      };
      broadcastOrBuffer({ type: "BROWSER_ACTION_START", toolName: tool_name, input });

      let result: { output: string; is_error: boolean };
      if (tabId !== null) {
        result = await executeActionInTab(tabId, tool_name, input);
      } else {
        result = { output: "No active tab to execute action on", is_error: true };
      }

      await postActionResult(sessionId, action_id, result);
      broadcastOrBuffer({ type: "BROWSER_ACTION_DONE", toolName: tool_name, result });
      break;
    }

    default:
      break;
  }
}

export default defineBackground(() => {
  browser.runtime.onMessage.addListener(
    (rawMsg: unknown, _sender, sendResponse) => {
      const msg = rawMsg as Record<string, unknown>;

      if (msg.type === "POPUP_OPENED") {
        popupAlive = true;
        const pending = missedMessages;
        const overflowed = bufferOverflowed;
        missedMessages = [];
        bufferOverflowed = false;
        sendResponse({
          ok: true,
          streaming: streamingState.active,
          missedMessages: pending,
          bufferOverflowed: overflowed,
        });
        return true;
      }

      if (msg.type === "POPUP_CLOSED") {
        popupAlive = false;
        sendResponse({ ok: true });
        return true;
      }

      if (msg.type === "SYNC_MESSAGES") {
        getCurrentSessionId()
          .then(async (sessionId) => {
            if (!sessionId) {
              sendResponse({ ok: true, messages: [], sessionId: null });
              return;
            }
            const [messages, info] = await Promise.all([
              fetchMessages(sessionId),
              fetchSessionInfo(sessionId),
            ]);
            sendResponse({
              ok: true,
              messages,
              sessionId,
              model: info?.model ?? null,
              usage: info?.usage ?? null,
            });
          })
          .catch((error) => sendResponse({ ok: false, error: String(error) }));
        return true;
      }

      if (msg.type === "USER_MESSAGE") {
        const text = msg.text as string;
        const browserContext = (msg.browserContext ?? {}) as Record<string, unknown>;
        getOrCreateSession()
          .then((sessionId) => {
            sendMessage(sessionId, text, browserContext).catch(console.error);
            sendResponse({ ok: true, sessionId });
          })
          .catch((error) => sendResponse({ ok: false, error: String(error) }));
        return true;
      }
      if (msg.type === "CAPTURE_CONTEXT") {
        browser.tabs.query({ active: true, currentWindow: true }).then(async (tabs) => {
          const tabId = tabs[0]?.id;
          if (!tabId) { sendResponse({}); return; }
          const ctx = await captureContext(tabId);
          sendResponse(ctx);
        }).catch(() => sendResponse({}));
        return true;
      }
      if (msg.type === "GET_CURRENT_SESSION") {
        getCurrentSessionId()
          .then((sessionId) => sendResponse({ sessionId }))
          .catch(() => sendResponse({ sessionId: null }));
        return true;
      }
      if (msg.type === "PERMISSION_RESPONSE") {
        const requestId = msg.requestId as string;
        const decision = msg.decision as "allow" | "deny" | "always_allow";
        getCurrentSessionId()
          .then((sessionId) => {
            if (!sessionId) throw new Error("No active session");
            return respondToPermission(sessionId, requestId, decision);
          })
          .then(() => sendResponse({ ok: true }))
          .catch((error) => sendResponse({ ok: false, error: String(error) }));
        return true;
      }
      if (msg.type === "NEW_SESSION") {
        createSession()
          .then((sessionId) => sendResponse({ ok: true, sessionId }))
          .catch((error) => sendResponse({ ok: false, error: String(error) }));
        return true;
      }
      if (msg.type === "LIST_SESSIONS") {
        listSessions()
          .then((sessions) => sendResponse({ ok: true, sessions }))
          .catch((error) => sendResponse({ ok: false, error: String(error) }));
        return true;
      }
      if (msg.type === "SELECT_SESSION") {
        selectSession(msg.sessionId as string)
          .then((payload) => sendResponse({ ok: true, ...payload }))
          .catch((error) => sendResponse({ ok: false, error: String(error) }));
        return true;
      }
      sendResponse({ ok: false, error: "Unknown message type" });
      return true;
    }
  );
});
