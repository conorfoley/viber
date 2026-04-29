<script lang="ts">
  import type { Message } from "../stores/conversation";

  export let msg: Message;

  const TOOL_LABELS: Record<string, string> = {
    browser_click: "Clicking",
    browser_type: "Typing",
    browser_scroll: "Scrolling",
    browser_navigate: "Navigating",
    browser_focus: "Focusing",
    browser_get_accessibility_tree: "Reading page",
  };

  function toolLabel(toolName: string): string {
    return TOOL_LABELS[toolName] ?? toolName;
  }
</script>

<div class="bubble {msg.role}">
  {#each msg.chunks as chunk}
    {#if chunk.kind === "text"}
      <span class="text">{chunk.content}</span>
    {:else}
      <span class="action-chip" class:done={chunk.done} class:error={chunk.error}>
        {#if !chunk.done}
          <span class="spinner" aria-hidden="true">⟳</span>
        {:else if chunk.error}
          <span>✗</span>
        {:else}
          <span>✓</span>
        {/if}
        {toolLabel(chunk.toolName)}
      </span>
    {/if}
  {/each}
</div>

<style>
  .bubble {
    max-width: 100%;
    padding: 8px 12px;
    border-radius: 10px;
    line-height: 1.5;
    word-break: break-word;
    white-space: pre-wrap;
  }

  .bubble.user {
    align-self: flex-end;
    background: #2563eb;
    color: #fff;
    border-bottom-right-radius: 3px;
  }

  .bubble.assistant {
    align-self: flex-start;
    background: #1e1e1e;
    color: #e8e8e8;
    border-bottom-left-radius: 3px;
  }

  .text {
    display: inline;
  }

  .action-chip {
    display: inline-flex;
    align-items: center;
    gap: 4px;
    background: #2a2a2a;
    border: 1px solid #3a3a3a;
    border-radius: 6px;
    padding: 2px 8px;
    font-size: 11px;
    color: #aaa;
    margin: 2px 0;
  }

  .action-chip.done {
    border-color: #2d6a2d;
    color: #6ec66e;
  }

  .action-chip.error {
    border-color: #6a2d2d;
    color: #c66e6e;
  }

  .spinner {
    display: inline-block;
    animation: spin 1s linear infinite;
  }

  @keyframes spin {
    from { transform: rotate(0deg); }
    to { transform: rotate(360deg); }
  }
</style>
