<script lang="ts">
  import type { Status } from "../stores/conversation";
  import { getToolLabel } from "../../../lib/shared";

  export let status: Status;
  export let action: string | null;

  $: tool = action ? getToolLabel(action) : null;
  $: label =
    status === "acting" && tool
      ? tool.label
      : status === "thinking"
      ? "Thinking…"
      : null;
  $: icon =
    status === "acting" && tool
      ? tool.icon
      : status === "thinking"
      ? "💭"
      : null;
</script>

{#if label}
  <div class="status" class:acting={status === "acting"}>
    <span class="status-icon">{icon}</span>
    <span class="status-label">{label}</span>
    <span class="dot-group">
      <span class="bounce-dot" style="animation-delay: 0s"></span>
      <span class="bounce-dot" style="animation-delay: 0.15s"></span>
      <span class="bounce-dot" style="animation-delay: 0.3s"></span>
    </span>
  </div>
{/if}

<style>
  .status {
    display: flex;
    align-items: center;
    gap: 5px;
    font-size: 11px;
    color: #999;
    background: #181818;
    border: 1px solid #2a2a2a;
    border-radius: 6px;
    padding: 3px 8px;
  }

  .status.acting {
    color: #f59e0b;
    border-color: #3d3010;
    background: #1a1708;
  }

  .status-icon {
    font-size: 12px;
    line-height: 1;
  }

  .status-label {
    font-weight: 500;
  }

  .dot-group {
    display: flex;
    gap: 2px;
    align-items: center;
    margin-left: 2px;
  }

  .bounce-dot {
    width: 3px;
    height: 3px;
    border-radius: 50%;
    background: currentColor;
    animation: bounce 1.2s ease-in-out infinite;
  }

  @keyframes bounce {
    0%, 80%, 100% { transform: translateY(0); opacity: 0.4; }
    40% { transform: translateY(-3px); opacity: 1; }
  }
</style>
