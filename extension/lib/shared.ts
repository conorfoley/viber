export const SESSION_LIST_LIMIT = 10;
export const MESSAGE_FETCH_LIMIT = 500;

export type MessageRole = "user" | "assistant";

export type MessageChunk =
  | { kind: "text"; content: string }
  | { kind: "action"; toolName: string; done: boolean; error: boolean };

export interface Message {
  id: string;
  role: MessageRole;
  chunks: MessageChunk[];
}

export type SessionSummary = {
  id: string;
  status: string;
  model?: string | null;
  title?: string | null;
  message_count?: number;
  last_activity?: string | null;
};

export type UserMessageResponse = {
  ok: boolean;
  sessionId?: string;
  error?: string;
};
