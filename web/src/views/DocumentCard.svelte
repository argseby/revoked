<script lang="ts">
  import Badge from '../components/Badge.svelte';
  import Button from '../components/Button.svelte';
  import Card from '../components/Card.svelte';
  import Icon from '../components/Icon.svelte';
  import { dropFiles } from '../lib/drop';
  import { isRedacted } from '../lib/filename';
  import { formatBytes } from '../lib/format';
  import { formatDate, t } from '../lib/i18n.svelte';
  import { canRedact } from '../lib/redaction/redaction.svelte';
  import { preview, staging, type Target } from '../lib/staging.svelte';
  import { isStampable, vault, type VaultRecord } from '../lib/vault.svelte';

  let {
    target,
    record,
    onredactexisting,
    ondelete,
  }: {
    target: Target;
    record: VaultRecord | undefined;
    onredactexisting: (r: VaultRecord) => void;
    ondelete: (r: VaultRecord) => void;
  } = $props();

  const busy = $derived(vault.isBusy(target.key));
  const redacted = $derived(isRedacted(record?.filename));
</script>

<div class="zone" use:dropFiles={{ ondrop: (files) => staging.drop(target, files) }}>
  <Card>
    <div class="doc">
      <div class="icon" class:filled={!!record}><Icon name={record ? 'file' : 'upload'} size={20} /></div>
      <div class="info stack-sm">
        <div class="row">
          <h3 class="title">{target.label}</h3>
          {#if record && redacted}
            <Badge tone="ok" icon="check" text={t('staging.redacted')} title={t('docs.redactedTitle')} />
          {:else if record && target.redact}
            <Badge tone="warn" icon="alert" text={t('docs.notRedacted')} title={t('docs.notRedactedTitle')} />
          {/if}
          {#if record && !isStampable(record)}
            <Badge tone="warn" icon="alert" text={t('docs.cantStamp')} title={t('docs.cantStampTitle')} />
          {/if}
        </div>
        {#if record}
          <p class="small muted">
            {record.filename} · {formatBytes(record.size ?? 0)} · {t('common.updated', { date: formatDate(record.updated) })}
          </p>
        {:else}
          <p class="small muted">{target.hint ?? t('docs.notUploaded')}</p>
        {/if}
      </div>
    </div>
    {#snippet actions()}
      <Button
        variant={record ? 'accent' : 'primary'}
        small
        icon="upload"
        busy={busy && !record}
        onclick={() => staging.begin(target)}>{record ? t('docs.replace') : t('docs.upload')}</Button
      >
      {#if record}
        <Button small icon="eye" onclick={() => preview.show(record)}>{t('docs.view')}</Button>
        {#if canRedact(record.mime ?? '')}
          <Button small icon="redact" {busy} onclick={() => onredactexisting(record)}>{t('docs.redact')}</Button>
        {/if}
        <Button small variant="destructive" icon="trash" onclick={() => ondelete(record)}>{t('common.delete')}</Button>
      {/if}
    {/snippet}
  </Card>
  <div class="overlay" aria-hidden="true"><Icon name="upload" size={20} /> {t('docs.dropHere')}</div>
</div>

<style>
  .zone {
    position: relative;
  }
  .overlay {
    display: none;
  }
  .zone:global([data-dragging]) .overlay {
    position: absolute;
    inset: 0;
    display: flex;
    align-items: center;
    justify-content: center;
    gap: var(--space-2);
    border: 2px dashed var(--primary);
    border-radius: var(--radius-lg);
    background: color-mix(in srgb, var(--primary-subtle) 88%, transparent);
    color: var(--primary);
    font-weight: 600;
    pointer-events: none;
  }
  .doc {
    display: flex;
    gap: var(--space-3);
    align-items: flex-start;
  }
  .icon {
    width: 40px;
    height: 40px;
    border-radius: var(--radius-md);
    display: grid;
    place-items: center;
    background: var(--sunken);
    color: var(--fg-muted);
    flex-shrink: 0;
  }
  .icon.filled {
    background: var(--primary-subtle);
    color: var(--primary);
  }
  .info {
    min-width: 0;
    flex: 1;
    gap: var(--space-1);
  }
  .info p {
    overflow-wrap: anywhere;
  }
</style>
