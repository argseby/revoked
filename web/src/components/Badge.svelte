<script lang="ts">
  import Icon, { type IconName } from './Icon.svelte';

  let {
    text,
    icon,
    tone = 'neutral',
    title,
  }: { text: string; icon?: IconName; tone?: 'neutral' | 'primary' | 'ok' | 'warn' | 'bad'; title?: string } =
    $props();
</script>

<span class="badge {tone}" {title}>
  {#if icon}<Icon name={icon} size={12} />{/if}
  {text}
</span>

<style>
  .badge {
    display: inline-flex;
    align-items: center;
    gap: var(--space-1);
    padding: 2px var(--space-2);
    border-radius: var(--radius-sm);
    font-size: 12px;
    font-weight: 550;
    background: var(--sunken);
    color: var(--fg-muted);
    white-space: nowrap;
  }
  .primary {
    background: var(--primary-subtle);
    color: var(--primary);
  }
  .ok {
    background: var(--ok-subtle);
    color: var(--ok);
  }
  .warn {
    background: var(--warn-subtle);
    color: var(--warn);
  }
  .bad {
    background: var(--bad-subtle);
    color: var(--bad);
  }
</style>
