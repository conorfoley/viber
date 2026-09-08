export const SESSION_LIST_LIMIT = 10;
export const MESSAGE_FETCH_LIMIT = 500;

export type MessageRole = "user" | "assistant";

export type MessageChunk =
  | { kind: "text"; content: string }
  | { kind: "thinking"; content: string }
  | { kind: "action"; toolName: string; done: boolean; error: boolean }
  | { kind: "tool"; toolName: string; toolId: string; done: boolean; error: boolean; output?: string };

export interface Message {
  id: string;
  role: MessageRole;
  chunks: MessageChunk[];
}

export type UsageInfo = {
  input_tokens: number;
  output_tokens: number;
  cache_creation_tokens: number;
  cache_read_tokens: number;
  turns: number;
  total_tokens: number;
};

export type SessionSummary = {
  id: string;
  status: string;
  model?: string | null;
  title?: string | null;
  message_count?: number;
  last_activity?: string | null;
  usage?: UsageInfo | null;
};

export type UserMessageResponse = {
  ok: boolean;
  sessionId?: string;
  error?: string;
};

export const TOOL_LABELS: Record<string, { label: string; icon: string }> = {
  browser_click: { label: "Click", icon: "🖱" },
  browser_type: { label: "Type", icon: "⌨" },
  browser_scroll: { label: "Scroll", icon: "↕" },
  browser_navigate: { label: "Navigate", icon: "🔗" },
  browser_focus: { label: "Focus", icon: "◎" },
  browser_get_accessibility_tree: { label: "Read page", icon: "📄" },
  browser_wait_for_load: { label: "Wait for load", icon: "⏳" },
  bash: { label: "Run command", icon: "▶" },
  read_file: { label: "Read file", icon: "📖" },
  write_file: { label: "Write file", icon: "✏" },
  edit_file: { label: "Edit file", icon: "✏" },
  glob: { label: "Find files", icon: "🔍" },
  grep: { label: "Search", icon: "🔍" },
  ls: { label: "List files", icon: "📁" },
  web_fetch: { label: "Fetch URL", icon: "🌐" },
  mcp_call: { label: "MCP call", icon: "🔌" },
};

export function getToolLabel(toolName: string): { label: string; icon: string } {
  return TOOL_LABELS[toolName] ?? { label: toolName, icon: "⚙" };
}
