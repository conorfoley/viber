import { describe, it, expect } from "vitest";
import { mapServerMessages, collectToolResults } from "../lib/messages";
import type { ServerMessage } from "../lib/messages";

describe("collectToolResults", () => {
  it("collects tool results keyed by tool_use_id", () => {
    const msgs: ServerMessage[] = [
      {
        role: "user",
        blocks: [
          { type: "tool_result", tool_use_id: "t1", name: "bash", is_error: false },
          { type: "tool_result", tool_use_id: "t2", name: "grep", is_error: true },
        ],
      },
    ];
    const results = collectToolResults(msgs);
    expect(results.size).toBe(2);
    expect(results.get("t1")).toEqual({ toolName: "bash", error: false });
    expect(results.get("t2")).toEqual({ toolName: "grep", error: true });
  });

  it("skips blocks without tool_use_id", () => {
    const msgs: ServerMessage[] = [
      { role: "user", blocks: [{ type: "tool_result" }] },
    ];
    expect(collectToolResults(msgs).size).toBe(0);
  });

  it("defaults error to false when is_error is missing", () => {
    const msgs: ServerMessage[] = [
      { role: "user", blocks: [{ type: "tool_result", tool_use_id: "t1", name: "ls" }] },
    ];
    expect(collectToolResults(msgs).get("t1")?.error).toBe(false);
  });

  it("prefers name over tool_name", () => {
    const msgs: ServerMessage[] = [
      { role: "user", blocks: [{ type: "tool_result", tool_use_id: "t1", name: "bash", tool_name: "old_bash" }] },
    ];
    expect(collectToolResults(msgs).get("t1")?.toolName).toBe("bash");
  });

  it("falls back to tool_name when name is missing", () => {
    const msgs: ServerMessage[] = [
      { role: "user", blocks: [{ type: "tool_result", tool_use_id: "t1", tool_name: "grep" }] },
    ];
    expect(collectToolResults(msgs).get("t1")?.toolName).toBe("grep");
  });
});

describe("mapServerMessages", () => {
  it("maps text blocks to text chunks", () => {
    const msgs: ServerMessage[] = [
      { role: "user", blocks: [{ type: "text", text: "hello" }] },
    ];
    const result = mapServerMessages(msgs);
    expect(result).toHaveLength(1);
    expect(result[0].role).toBe("user");
    expect(result[0].chunks).toEqual([{ kind: "text", content: "hello" }]);
  });

  it("maps thinking blocks to thinking chunks", () => {
    const msgs: ServerMessage[] = [
      { role: "assistant", blocks: [{ type: "thinking", text: "let me think..." }] },
    ];
    const result = mapServerMessages(msgs);
    expect(result[0].chunks).toEqual([{ kind: "thinking", content: "let me think..." }]);
  });

  it("maps tool_use blocks to tool chunks with matched results", () => {
    const msgs: ServerMessage[] = [
      {
        role: "assistant",
        blocks: [{ type: "tool_use", id: "t1", name: "bash" }],
      },
      {
        role: "user",
        blocks: [{ type: "tool_result", tool_use_id: "t1", name: "bash", is_error: false }],
      },
    ];
    const result = mapServerMessages(msgs);
    const assistantMsg = result.find((m) => m.role === "assistant");
    expect(assistantMsg?.chunks).toEqual([
      { kind: "tool", toolName: "bash", toolId: "t1", done: true, error: false },
    ]);
  });

  it("maps browser tool_use to action chunks", () => {
    const msgs: ServerMessage[] = [
      {
        role: "assistant",
        blocks: [{ type: "tool_use", id: "t1", name: "browser_click" }],
      },
    ];
    const result = mapServerMessages(msgs);
    expect(result[0].chunks).toEqual([
      { kind: "action", toolName: "browser_click", done: true, error: false },
    ]);
  });

  it("marks tool error from result", () => {
    const msgs: ServerMessage[] = [
      {
        role: "assistant",
        blocks: [{ type: "tool_use", id: "t1", name: "bash" }],
      },
      {
        role: "user",
        blocks: [{ type: "tool_result", tool_use_id: "t1", name: "bash", is_error: true }],
      },
    ];
    const result = mapServerMessages(msgs);
    const chunk = result.find((m) => m.role === "assistant")?.chunks[0];
    expect(chunk).toMatchObject({ kind: "tool", error: true });
  });

  it("skips messages with non-user/assistant roles", () => {
    const msgs: ServerMessage[] = [
      { role: "system", blocks: [{ type: "text", text: "system prompt" }] },
      { role: "user", blocks: [{ type: "text", text: "hello" }] },
    ];
    const result = mapServerMessages(msgs);
    expect(result).toHaveLength(1);
    expect(result[0].role).toBe("user");
  });

  it("skips messages with no parseable blocks", () => {
    const msgs: ServerMessage[] = [
      { role: "assistant", blocks: [{ type: "unknown_block_type" }] },
    ];
    expect(mapServerMessages(msgs)).toHaveLength(0);
  });

  it("skips text blocks with empty text", () => {
    const msgs: ServerMessage[] = [
      { role: "assistant", blocks: [{ type: "text", text: "" }] },
    ];
    expect(mapServerMessages(msgs)).toHaveLength(0);
  });

  it("assigns sequential ids", () => {
    const msgs: ServerMessage[] = [
      { role: "user", blocks: [{ type: "text", text: "one" }] },
      { role: "assistant", blocks: [{ type: "text", text: "two" }] },
      { role: "user", blocks: [{ type: "text", text: "three" }] },
    ];
    const result = mapServerMessages(msgs);
    expect(result.map((m) => m.id)).toEqual(["1", "2", "3"]);
  });

  it("handles multiple chunks in one message", () => {
    const msgs: ServerMessage[] = [
      {
        role: "assistant",
        blocks: [
          { type: "thinking", text: "hmm" },
          { type: "text", text: "hello" },
          { type: "tool_use", id: "t1", name: "bash" },
        ],
      },
    ];
    const result = mapServerMessages(msgs);
    expect(result[0].chunks).toHaveLength(3);
    expect(result[0].chunks[0].kind).toBe("thinking");
    expect(result[0].chunks[1].kind).toBe("text");
    expect(result[0].chunks[2].kind).toBe("tool");
  });

  it("falls back toolName to 'tool' when no name available", () => {
    const msgs: ServerMessage[] = [
      {
        role: "assistant",
        blocks: [{ type: "tool_use", id: "t1" }],
      },
    ];
    const result = mapServerMessages(msgs);
    expect(result[0].chunks[0]).toMatchObject({ kind: "tool", toolName: "tool" });
  });
});
