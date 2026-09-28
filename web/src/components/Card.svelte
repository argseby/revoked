<script lang="ts">
  import type { Snippet } from 'svelte';

  let { children, actions, pad = true }: { children: Snippet; actions?: Snippet; pad?: boolean } = $props();
</script>

<section class="card">
  <div class:pad>{@render children()}</div>
  {#if actions}
    <div class="actions">{@render actions()}</div>
  {/if}
</section>

<style>
  .card {
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: var(--radius-lg);
    overflow: hidden;
  }
  .pad {
    padding: var(--space-4);
  }
  .actions {
    display: flex;
    flex-wrap: wrap;
    gap: var(--space-2);
    padding: var(--space-3) var(--space-4);
    border-top: 1px solid var(--border);
  }
</style>
