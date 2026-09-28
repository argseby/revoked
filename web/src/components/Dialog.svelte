<script lang="ts">
  import { t } from '../lib/i18n.svelte';
  import type { Snippet } from 'svelte';
  import Button from './Button.svelte';

  // A native <dialog>: focus trapping, Escape and the backdrop come from the
  // browser. `open` is owned by the caller; closing only reports back.
  let {
    open,
    title,
    onclose,
    wide = false,
    full = false,
    children,
    footer,
  }: {
    open: boolean;
    title: string;
    onclose: () => void;
    wide?: boolean;
    full?: boolean;
    children: Snippet;
    footer?: Snippet;
  } = $props();

  let dialog: HTMLDialogElement | undefined = $state();

  $effect(() => {
    if (!dialog) return;
    if (open && !dialog.open) dialog.showModal();
    if (!open && dialog.open) dialog.close();
  });
</script>

<dialog
  bind:this={dialog}
  class:wide
  class:full
  aria-label={title}
  oncancel={(e) => {
    e.preventDefault();
    onclose();
  }}
>
  {#if open}
    <header>
      <h2 class="header">{title}</h2>
      <Button icon="close" tooltip={t('common.close')} onclick={onclose} />
    </header>
    <div class="body">{@render children()}</div>
    {#if footer}
      <footer>{@render footer()}</footer>
    {/if}
  {/if}
</dialog>

<style>
  dialog {
    width: min(560px, calc(100vw - 2 * var(--space-4)));
    max-height: calc(100dvh - 2 * var(--space-4));
    padding: 0;
    border: 1px solid var(--border);
    border-radius: var(--radius-lg);
    background: var(--surface);
    color: var(--fg);
    display: none;
    flex-direction: column;
    overflow: hidden;
  }
  dialog[open] {
    display: flex;
    animation: fade var(--motion);
  }
  dialog.wide {
    width: min(760px, calc(100vw - 2 * var(--space-4)));
  }
  dialog.full {
    width: min(1100px, 100vw);
    height: 100dvh;
    max-height: 100dvh;
    border-radius: 0;
  }
  @media (min-width: 900px) {
    dialog.full {
      height: calc(100dvh - 2 * var(--space-6));
      border-radius: var(--radius-lg);
    }
  }
  dialog::backdrop {
    background: var(--scrim);
  }
  header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: var(--space-3);
    padding: var(--space-3) var(--space-3) var(--space-3) var(--space-5);
    border-bottom: 1px solid var(--border);
  }
  .body {
    padding: var(--space-5);
    overflow: auto;
    flex: 1;
    min-height: 0;
  }
  dialog.full .body {
    padding: 0;
    display: flex;
    flex-direction: column;
  }
  footer {
    display: flex;
    justify-content: flex-end;
    flex-wrap: wrap;
    gap: var(--space-2);
    padding: var(--space-3) var(--space-5);
    border-top: 1px solid var(--border);
  }
  @keyframes fade {
    from {
      opacity: 0;
    }
  }
</style>
