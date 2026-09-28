<script lang="ts">
  import type { Snippet } from 'svelte';
  import Icon, { type IconName } from './Icon.svelte';
  import Spinner from './Spinner.svelte';

  // The one button. `accent` is every control that is neither the screen's
  // main action nor destructive; an icon-only button needs a tooltip, which is
  // also its accessible name.
  let {
    variant = 'accent',
    icon,
    tooltip,
    small = false,
    busy = false,
    disabled = false,
    type = 'button',
    form,
    onclick,
    children,
  }: {
    variant?: 'primary' | 'accent' | 'destructive';
    icon?: IconName;
    tooltip?: string;
    small?: boolean;
    busy?: boolean;
    disabled?: boolean;
    type?: 'button' | 'submit';
    // Submits the form with this id from outside it, as a dialog footer does.
    form?: string;
    onclick?: (e: MouseEvent) => void;
    children?: Snippet;
  } = $props();
</script>

<button
  class="btn {variant}"
  class:small
  class:icon-only={!children}
  {type}
  {form}
  title={tooltip}
  aria-label={children ? undefined : tooltip}
  aria-busy={busy}
  disabled={disabled || busy}
  {onclick}
>
  {#if busy}
    <Spinner />
  {:else if icon}
    <Icon name={icon} size={small ? 14 : 16} />
  {/if}
  {#if children}<span>{@render children()}</span>{/if}
</button>

<style>
  .btn {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    gap: var(--space-2);
    min-height: 36px;
    padding: 0 var(--space-4);
    border-radius: var(--radius-md);
    border: 1px solid var(--border);
    background: var(--surface);
    color: var(--fg);
    font-weight: 550;
    cursor: pointer;
    white-space: nowrap;
    transition: background var(--motion), opacity var(--motion);
  }
  .btn:hover:not(:disabled) {
    background: var(--hover);
  }
  .btn.primary {
    background: var(--primary);
    border-color: var(--primary);
    color: var(--on-primary);
  }
  .btn.primary:hover:not(:disabled) {
    background: var(--primary);
    opacity: 0.9;
  }
  .btn.destructive {
    color: var(--bad);
    border-color: var(--bad);
  }
  .btn.destructive:hover:not(:disabled) {
    background: var(--bad-subtle);
  }
  .btn.small {
    min-height: 30px;
    padding: 0 var(--space-3);
    font-size: 12px;
  }
  .btn.icon-only {
    padding: 0;
    width: 36px;
  }
  .btn.icon-only.small {
    width: 30px;
  }
  .btn:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }
</style>
