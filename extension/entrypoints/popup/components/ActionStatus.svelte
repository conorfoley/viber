<script lang="ts">
  import type { Status } from "../stores/conversation";

  export let status: Status;
  export let action: string | null;

  const TOOL_LABELS: Record<string, string> = {
    browser_click: "clicking",
    browser_type: "typing",
    browser_scroll: "scrolling",
    browser_navigate: "navigating",
    browser_focus: "focusing",
    browser_get_accessibility_tree: "reading page",
  };

  $: label =
    status === "acting" && action
      ? TOOL_LABELS[action] ?? action
      : status === "thinking"
      ? "thinking…"
      : null;
</script>

{#if label}
  <div class="status" class:acting={status === "acting"}>
    <span class="dot"></span>
    {label}
  </div>
{/if}

<style>
  .status {
    display: flex;
    align-items: center;
    gap: 5px;
    font-size: 11px;
    color: #888;
  }

  .status.acting {
    color: #f59e0b;
  }

  .dot {
    width: 6px;
    height: 6px;
    border-radius: 50%;
    background: currentColor;
    animation: pulse 1.2s ease-in-out infinite;
  }

  @keyframes pulse {
    0%, 100% { opacity: 1; }
    50% { opacity: 0.3; }
  }
</style>
