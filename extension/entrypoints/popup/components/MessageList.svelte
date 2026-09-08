<script lang="ts">
  import { afterUpdate, beforeUpdate } from "svelte";
  import type { Message } from "../stores/conversation";
  import MessageBubble from "./MessageBubble.svelte";

  export let messages: Message[];

  let listEl: HTMLElement;
  let shouldAutoScroll = true;

  beforeUpdate(() => {
    if (listEl) {
      const threshold = 60;
      shouldAutoScroll =
        listEl.scrollTop + listEl.clientHeight >= listEl.scrollHeight - threshold;
    }
  });

  afterUpdate(() => {
    if (listEl && shouldAutoScroll) {
      listEl.scrollTop = listEl.scrollHeight;
    }
  });
</script>

<div class="list" bind:this={listEl}>
  {#if messages.length === 0}
    <div class="empty">Ask Viber to do something on this page…</div>
  {/if}
  {#each messages as msg (msg.id)}
    <MessageBubble {msg} />
  {/each}
</div>

<style>
  .list {
    flex: 1;
    overflow-y: auto;
    padding: 12px 14px;
    display: flex;
    flex-direction: column;
    gap: 10px;
    scroll-behavior: smooth;
  }

  .empty {
    color: #555;
    font-style: italic;
    text-align: center;
    margin-top: 40px;
  }
</style>
