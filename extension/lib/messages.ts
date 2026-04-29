import type { Message, MessageChunk } from "./shared";

export type ServerBlock = {
  type: string;
  id?: string;
  tool_use_id?: string;
  text?: string;
  name?: string;
  tool_name?: string;
  is_error?: boolean;
};

export type ServerMessage = {
  role: string;
  blocks: ServerBlock[];
};

type ToolResultSummary = {
  toolName?: string;
  error: boolean;
};

export function collectToolResults(serverMessages: ServerMessage[]): Map<string, ToolResultSummary> {
  const results = new Map<string, ToolResultSummary>();

  for (const msg of serverMessages) {
    for (const block of msg.blocks) {
      if (block.type === "tool_result" && block.tool_use_id) {
        results.set(block.tool_use_id, {
          toolName: block.name ?? block.tool_name,
          error: block.is_error ?? false,
        });
      }
    }
  }

  return results;
}

export function mapServerMessages(serverMessages: ServerMessage[]): Message[] {
  let id = 0;
  const toolResults = collectToolResults(serverMessages);

  return serverMessages.flatMap((msg) => {
    if (msg.role !== "user" && msg.role !== "assistant") return [];

    const chunks = msg.blocks.flatMap((block): MessageChunk[] => {
      if (block.type === "text" && block.text) {
        return [{ kind: "text", content: block.text }];
      }

      if (block.type === "thinking" && block.text) {
        return [{ kind: "thinking", content: block.text }];
      }

      if (msg.role === "assistant" && block.type === "tool_use") {
        const result = block.id ? toolResults.get(block.id) : undefined;
        const toolName = result?.toolName ?? block.name ?? "tool";
        const isBrowserTool = toolName.startsWith("browser_");
        if (isBrowserTool) {
          return [{
            kind: "action",
            toolName,
            done: true,
            error: result?.error ?? false,
          }];
        }
        return [{
          kind: "tool",
          toolName,
          toolId: block.id ?? "",
          done: true,
          error: result?.error ?? false,
        }];
      }

      return [];
    });

    if (chunks.length === 0) return [];
    id += 1;
    return [{ id: String(id), role: msg.role as "user" | "assistant", chunks }];
  });
}
