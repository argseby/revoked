<script lang="ts">
  import type { Snippet } from 'svelte';
  import Icon from './Icon.svelte';

  let { tone = 'warn', children }: { tone?: 'warn' | 'bad' | 'info'; children: Snippet } = $props();
</script>

<div class="alert {tone}" role={tone === 'bad' ? 'alert' : 'status'}>
  <Icon name={tone === 'info' ? 'shield' : 'alert'} />
  <div>{@render children()}</div>
</div>

<style>
  .alert {
    display: flex;
    gap: var(--space-2);
    align-items: flex-start;
    padding: var(--space-3);
    border-radius: var(--radius-md);
    font-size: 13px;
  }
  .alert :global(svg) {
    flex-shrink: 0;
    margin-top: 2px;
  }
  .warn {
    background: var(--warn-subtle);
    color: var(--warn);
  }
  .bad {
    background: var(--bad-subtle);
    color: var(--bad);
  }
  .info {
    background: var(--primary-subtle);
    color: var(--primary);
  }
</style>
