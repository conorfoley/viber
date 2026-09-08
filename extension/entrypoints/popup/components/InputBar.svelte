<script lang="ts">
  import { createEventDispatcher } from "svelte";

  export let disabled = false;

  const dispatch = createEventDispatcher<{ send: string }>();

  let value = "";

  function submit() {
    const text = value.trim();
    if (!text || disabled) return;
    value = "";
    dispatch("send", text);
  }

  function handleKeydown(e: KeyboardEvent) {
    if (e.key === "Enter" && !e.shiftKey) {
      e.preventDefault();
      submit();
    }
  }
</script>

<div class="bar">
  <textarea
    bind:value
    on:keydown={handleKeydown}
    {disabled}
    placeholder={disabled ? "Waiting…" : "Ask Viber anything about this page…"}
    rows="2"
  ></textarea>
  <button on:click={submit} {disabled} aria-label="Send">
    <svg width="16" height="16" viewBox="0 0 16 16" fill="currentColor">
      <path d="M1 1l14 7-14 7V9.5l10-1.5-10-1.5V1z" />
    </svg>
  </button>
</div>

<style>
  .bar {
    display: flex;
    gap: 6px;
    align-items: flex-end;
    padding: 10px 14px;
    background: #1a1a1a;
    border-top: 1px solid #2a2a2a;
    flex-shrink: 0;
  }

  textarea {
    flex: 1;
    background: #111;
    border: 1px solid #333;
    border-radius: 8px;
    color: #e8e8e8;
    font-family: inherit;
    font-size: 13px;
    line-height: 1.4;
    padding: 7px 10px;
    resize: none;
    outline: none;
    transition: border-color 0.15s;
  }

  textarea:focus {
    border-color: #555;
  }

  textarea:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }

  button {
    background: #2563eb;
    border: none;
    border-radius: 8px;
    color: #fff;
    cursor: pointer;
    padding: 8px 10px;
    display: flex;
    align-items: center;
    justify-content: center;
    transition: background 0.15s;
    flex-shrink: 0;
  }

  button:hover:not(:disabled) {
    background: #1d4ed8;
  }

  button:disabled {
    opacity: 0.4;
    cursor: not-allowed;
  }
</style>
