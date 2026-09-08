<script lang="ts">
  import type { Message } from "../stores/conversation";
  import { getToolLabel } from "../../../lib/shared";

  export let msg: Message;

  let expandedThinking: Record<number, boolean> = {};

  function toggleThinking(index: number): void {
    expandedThinking[index] = !expandedThinking[index];
    expandedThinking = expandedThinking;
  }
</script>

<div class="bubble {msg.role}">
  {#each msg.chunks as chunk, i}
    {#if chunk.kind === "text"}
      <span class="text">{chunk.content}</span>
    {:else if chunk.kind === "thinking"}
      <div class="thinking-block">
        <button class="thinking-toggle" on:click={() => toggleThinking(i)}>
          <span class="thinking-icon">💭</span>
          <span>Thinking</span>
          <span class="thinking-arrow" class:expanded={expandedThinking[i]}>▸</span>
        </button>
        {#if expandedThinking[i]}
          <div class="thinking-content">{chunk.content}</div>
        {/if}
      </div>
    {:else if chunk.kind === "tool" || chunk.kind === "action"}
      {@const tool = getToolLabel(chunk.toolName)}
      <div class="action-row" class:running={!chunk.done} class:done={chunk.done && !chunk.error} class:error={chunk.done && chunk.error}>
        <span class="action-icon">{tool.icon}</span>
        <span class="action-label">{tool.label}</span>
        {#if !chunk.done}
          <span class="action-status-badge running-badge">
            <span class="pulse-ring"></span>
            running
          </span>
        {:else if chunk.error}
          <span class="action-status-badge error-badge">✗ failed</span>
        {:else}
          <span class="action-status-badge done-badge">✓</span>
        {/if}
      </div>
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

  .thinking-block {
    margin: 5px 0;
    border-radius: 6px;
    overflow: hidden;
  }

  .thinking-toggle {
    display: flex;
    align-items: center;
    gap: 5px;
    width: 100%;
    background: #1a1520;
    border: 1px solid #2a2535;
    border-radius: 6px;
    color: #a78bfa;
    cursor: pointer;
    font-family: inherit;
    font-size: 11px;
    font-weight: 500;
    padding: 4px 8px;
    text-align: left;
    transition: background 0.15s;
  }

  .thinking-toggle:hover {
    background: #221a2e;
  }

  .thinking-icon {
    font-size: 12px;
  }

  .thinking-arrow {
    margin-left: auto;
    transition: transform 0.15s;
    font-size: 10px;
  }

  .thinking-arrow.expanded {
    transform: rotate(90deg);
  }

  .thinking-content {
    background: #15111a;
    border: 1px solid #2a2535;
    border-top: none;
    border-radius: 0 0 6px 6px;
    color: #9a8bba;
    font-size: 11px;
    line-height: 1.5;
    max-height: 200px;
    overflow-y: auto;
    padding: 8px;
    white-space: pre-wrap;
  }

  .action-row {
    display: flex;
    align-items: center;
    gap: 7px;
    background: #161616;
    border: 1px solid #2a2a2a;
    border-radius: 8px;
    padding: 6px 10px;
    margin: 5px 0;
    font-size: 12px;
    transition: border-color 0.2s, background 0.2s;
  }

  .action-row.running {
    border-color: #b4860d;
    background: #1a1708;
  }

  .action-row.done {
    border-color: #264a26;
    background: #111a11;
  }

  .action-row.error {
    border-color: #5a2020;
    background: #1a1111;
  }

  .action-icon {
    flex-shrink: 0;
    font-size: 14px;
    line-height: 1;
  }

  .action-label {
    flex: 1;
    color: #ccc;
    font-weight: 500;
    min-width: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .action-status-badge {
    flex-shrink: 0;
    font-size: 10px;
    font-weight: 600;
    letter-spacing: 0.03em;
    text-transform: uppercase;
    display: inline-flex;
    align-items: center;
    gap: 4px;
  }

  .running-badge {
    color: #f59e0b;
  }

  .done-badge {
    color: #4ade80;
  }

  .error-badge {
    color: #f87171;
  }

  .pulse-ring {
    width: 6px;
    height: 6px;
    border-radius: 50%;
    background: #f59e0b;
    animation: pulse-glow 1.4s ease-in-out infinite;
  }

  @keyframes pulse-glow {
    0%, 100% { opacity: 1; box-shadow: 0 0 0 0 rgba(245, 158, 11, 0.5); }
    50% { opacity: 0.5; box-shadow: 0 0 0 4px rgba(245, 158, 11, 0); }
  }
</style>
