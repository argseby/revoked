<script lang="ts">
  import Alert from '../components/Alert.svelte';
  import Button from '../components/Button.svelte';
  import Spinner from '../components/Spinner.svelte';
  import { confirm } from '../lib/confirm.svelte';
  import { dropFiles } from '../lib/drop';
  import { t } from '../lib/i18n.svelte';
  import type { MessageKey } from '../lib/locales/en';
  import { staging, type Target } from '../lib/staging.svelte';
  import { documentSlots } from '../lib/tenant';
  import { vault, type VaultRecord } from '../lib/vault.svelte';
  import DocumentCard from './DocumentCard.svelte';
  import FileDialogs from './FileDialogs.svelte';

  const slotKeys = new Set(documentSlots.map((s) => s.key));
  const slots = $derived<Target[]>(
    documentSlots.map((s) => ({
      key: s.key,
      label: t(`slot.${s.key}` as MessageKey),
      hint: t(`slot.${s.key}.hint` as MessageKey),
      redact: s.redact,
    })),
  );
  const others = $derived(vault.files.filter((r) => !slotKeys.has(r.key)));

  async function redactExisting(r: VaultRecord) {
    const ok = await confirm.ask({
      title: t('docs.redactExisting.title'),
      message: t('docs.redactExisting.message'),
      action: t('common.continue'),
    });
    if (ok) await staging.redactExisting(r);
  }

  async function remove(r: VaultRecord) {
    const ok = await confirm.ask({
      title: t('docs.delete.title', { label: r.label || r.key }),
      message: t('docs.delete.message'),
      action: t('common.delete'),
      destructive: true,
    });
    if (ok) await vault.remove(r);
  }
</script>

<div class="stack page" use:dropFiles={{ ondrop: (files) => staging.drop(null, files), disabled: staging.open }}>
  <div class="spread">
    <div class="stack-sm intro">
      <h1 class="header">{t('docs.title')}</h1>
      <p class="muted">{t('docs.intro')}</p>
    </div>
    <Button variant="primary" icon="plus" onclick={() => staging.begin(null)}>{t('docs.add')}</Button>
  </div>
  <p class="small muted drop-hint">{t('docs.dropHint')}</p>

  {#if vault.error}<Alert tone="bad">{vault.error}</Alert>{/if}
  {#if staging.error && !staging.open}<Alert tone="bad">{staging.error}</Alert>{/if}

  {#if !vault.loaded && vault.loading}
    <div class="center"><Spinner large /></div>
  {:else}
    {#each slots as slot (slot.key)}
      <DocumentCard target={slot} record={vault.byKey.get(slot.key)} onredactexisting={redactExisting} ondelete={remove} />
    {/each}

    {#if others.length}
      <h2 class="title section">{t('docs.others')}</h2>
      {#each others as r (r.id)}
        <DocumentCard
          target={{ key: r.key, label: r.label || r.key }}
          record={r}
          onredactexisting={redactExisting}
          ondelete={remove}
        />
      {/each}
    {/if}
  {/if}
</div>

<FileDialogs />

<style>
  .page {
    min-height: 60vh;
    border-radius: var(--radius-lg);
    outline: 2px dashed transparent;
    outline-offset: var(--space-2);
    transition: outline-color var(--motion);
  }
  .page:global([data-dragging]) {
    outline-color: var(--primary);
  }
  .intro {
    max-width: 520px;
  }
  .drop-hint {
    margin-top: calc(-1 * var(--space-2));
  }
  @media (pointer: coarse) {
    .drop-hint {
      display: none;
    }
  }
  .center {
    display: grid;
    place-items: center;
    padding: var(--space-6);
  }
  .section {
    margin-top: var(--space-2);
  }
</style>
