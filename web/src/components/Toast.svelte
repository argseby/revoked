<script lang="ts">
  import { toast } from '../lib/confirm.svelte';

  // A manual popover joins the top layer, so the toast shows above an open
  // modal dialog instead of underneath its backdrop.
  let host: HTMLDivElement | undefined = $state();

  $effect(() => {
    if (!host) return;
    const open = host.matches(':popover-open');
    if (toast.message) {
      if (open) host.hidePopover();
      host.showPopover();
    } else if (open) {
      host.hidePopover();
    }
  });
</script>

<div bind:this={host} popover="manual" class="toast" role="status" aria-live="polite">{toast.message}</div>

<style>
  .toast {
    inset: auto 0 var(--space-6) 0;
    margin: 0 auto;
    border: 0;
    background: var(--fg);
    color: var(--bg);
    padding: var(--space-3) var(--space-4);
    border-radius: var(--radius-md);
    font-weight: 550;
    max-width: min(480px, calc(100vw - 2 * var(--space-4)));
  }
</style>
