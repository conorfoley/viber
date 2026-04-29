import { writable } from "svelte/store";
import type { Message } from "../../../lib/shared";

export type { MessageRole, MessageChunk, Message } from "../../../lib/shared";

export type Status = "idle" | "thinking" | "acting";

const STORAGE_KEY = "viber_conversation";

export const messages = writable<Message[]>([]);
export const status = writable<Status>("idle");
export const currentAction = writable<string | null>(null);

let msgIdCounter = 0;

browser.storage.local.get(STORAGE_KEY).then((stored) => {
  const data = stored[STORAGE_KEY] as { messages: Message[]; counter: number } | undefined;
  if (data?.messages?.length) {
    messages.set(data.messages);
    msgIdCounter = data.counter ?? data.messages.length;
  }
});

messages.subscribe((msgs) => {
  browser.storage.local.set({ [STORAGE_KEY]: { messages: msgs, counter: msgIdCounter } });
});

function nextId(): string {
  return String(++msgIdCounter);
}

export function setMessages(nextMessages: Message[]): void {
  messages.set(nextMessages);
  msgIdCounter = nextMessages.reduce((max, msg) => {
    const numericId = Number(msg.id);
    return Number.isFinite(numericId) ? Math.max(max, numericId) : max;
  }, nextMessages.length);
}

export function addUserMessage(text: string): void {
  messages.update((list) => [
    ...list,
    { id: nextId(), role: "user", chunks: [{ kind: "text", content: text }] },
  ]);
}

export function startAssistantMessage(): string {
  const id = nextId();
  messages.update((list) => [
    ...list,
    { id, role: "assistant", chunks: [] },
  ]);
  return id;
}

export function appendDelta(id: string, text: string): void {
  messages.update((list) =>
    list.map((msg) => {
      if (msg.id !== id) return msg;
      const chunks = [...msg.chunks];
      const last = chunks[chunks.length - 1];
      if (last?.kind === "text") {
        chunks[chunks.length - 1] = { kind: "text", content: last.content + text };
      } else {
        chunks.push({ kind: "text", content: text });
      }
      return { ...msg, chunks };
    })
  );
}

export function appendAction(
  id: string,
  toolName: string,
  done: boolean,
  error = false
): void {
  messages.update((list) =>
    list.map((msg) => {
      if (msg.id !== id) return msg;
      const chunks = [...msg.chunks];
      const lastIdx = chunks.length - 1;
      const last = chunks[lastIdx];
      if (last?.kind === "action" && last.toolName === toolName && !last.done) {
        chunks[lastIdx] = { kind: "action", toolName, done, error };
      } else {
        chunks.push({ kind: "action", toolName, done, error });
      }
      return { ...msg, chunks };
    })
  );
}
