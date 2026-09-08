import { describe, it, expect } from "vitest";
import { getToolLabel, TOOL_LABELS } from "../lib/shared";

describe("getToolLabel", () => {
  it("returns known label for registered tool", () => {
    const result = getToolLabel("bash");
    expect(result).toEqual({ label: "Run command", icon: "▶" });
  });

  it("returns known label for browser tool", () => {
    const result = getToolLabel("browser_click");
    expect(result).toEqual({ label: "Click", icon: "🖱" });
  });

  it("falls back to toolName and gear icon for unknown tool", () => {
    const result = getToolLabel("some_custom_tool");
    expect(result).toEqual({ label: "some_custom_tool", icon: "⚙" });
  });

  it("has entries for all expected tools", () => {
    const expected = [
      "browser_click", "browser_type", "browser_scroll", "browser_navigate",
      "browser_focus", "browser_get_accessibility_tree", "bash", "read_file",
      "write_file", "edit_file", "glob", "grep", "ls", "web_fetch", "mcp_call",
    ];
    for (const name of expected) {
      expect(TOOL_LABELS).toHaveProperty(name);
    }
  });
});
