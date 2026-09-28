<script lang="ts">
  import type { Snippet } from 'svelte';

  let {
    checked,
    onchange,
    disabled = false,
    children,
    trailing,
  }: { checked: boolean; onchange: () => void; disabled?: boolean; children: Snippet; trailing?: Snippet } =
    $props();
</script>

<label class="check" class:disabled>
  <input type="checkbox" {checked} {disabled} {onchange} />
  <span class="text">{@render children()}</span>
  {#if trailing}<span class="trailing">{@render trailing()}</span>{/if}
</label>

<style>
  .check {
    display: flex;
    align-items: center;
    gap: var(--space-3);
    padding: var(--space-2) var(--space-3);
    border-radius: var(--radius-md);
    cursor: pointer;
  }
  .check:hover {
    background: var(--hover);
  }
  .disabled {
    opacity: 0.6;
    cursor: not-allowed;
  }
  input {
    width: 18px;
    height: 18px;
    accent-color: var(--primary);
    flex-shrink: 0;
  }
  .text {
    flex: 1;
    min-width: 0;
  }
  .trailing {
    flex-shrink: 0;
  }
</style>
