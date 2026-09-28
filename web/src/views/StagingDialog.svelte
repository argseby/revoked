<script lang="ts">
  import Alert from '../components/Alert.svelte';
  import Badge from '../components/Badge.svelte';
  import Button from '../components/Button.svelte';
  import Dialog from '../components/Dialog.svelte';
  import Icon from '../components/Icon.svelte';
  import TextField from '../components/TextField.svelte';
  import { dropFiles } from '../lib/drop';
  import { formatBytes } from '../lib/format';
  import { t } from '../lib/i18n.svelte';
  import { staging } from '../lib/staging.svelte';

  let input: HTMLInputElement | undefined = $state();

  const title = $derived(staging.target ? staging.target.label : t('staging.addTitle'));
  const suggestRedact = $derived(!!staging.target?.redact && staging.redactable && !staging.redacted);

  function change(e: Event) {
    const el = e.currentTarget as HTMLInputElement;
    const files = Array.from(el.files ?? []);
    if (files.length) staging.drop(staging.target, files);
    el.value = '';
  }
</script>

<Dialog open={staging.open && !staging.editorOpen} {title} onclose={() => staging.close()}>
  <div class="stack" use:dropFiles={{ ondrop: (files) => staging.drop(staging.target, files) }}>
    {#if staging.needsLabel}
      <TextField
        label={t('staging.name')}
        placeholder={t('staging.namePlaceholder')}
        bind:value={staging.newLabel}
        maxlength={80}
      />
    {/if}

    {#if staging.target?.hint}
      <p class="muted">{staging.target.hint}</p>
    {/if}

    <input
      bind:this={input}
      class="sr-only"
      type="file"
      accept="image/*,application/pdf"
      multiple={staging.needsLabel}
      onchange={change}
      tabindex="-1"
    />

    {#if staging.file}
      <div class="staged">
        {#if staging.previewUrl}
          <img src={staging.previewUrl} alt={staging.filename} />
        {:else}
          <div class="doc-icon"><Icon name="file" size={32} /><span class="small muted">{t('staging.pdfPreview')}</span></div>
        {/if}
        <div class="spread meta">
          <span class="small mono">{staging.filename} · {formatBytes(staging.file.size)}</span>
          <div class="row">
            {#if staging.redacted}<Badge tone="ok" icon="check" text={t('staging.redacted')} />{/if}
            {#if staging.queue.length}<Badge text="+{staging.queue.length}" />{/if}
            <Button small onclick={() => input?.click()}>{t('staging.chooseAnother')}</Button>
          </div>
        </div>
      </div>

      {#if suggestRedact}
        <Alert tone="warn">{t('staging.suggestRedact')}</Alert>
      {:else if !staging.stampable && staging.isImage}
        <Alert tone="warn">{t('staging.convert')}</Alert>
      {:else if !staging.stampable}
        <Alert tone="warn">{t('staging.unstampable')}</Alert>
      {/if}
    {:else}
      <button class="drop" type="button" onclick={() => input?.click()}>
        <Icon name="upload" size={24} />
        <span class="title">{t('staging.choose')}</span>
        <span class="small muted">{t('staging.chooseOrDrop')} · {t('staging.kinds')}</span>
      </button>
    {/if}

    {#if staging.error}
      <Alert tone="bad">{staging.error}</Alert>
    {/if}
  </div>

  {#snippet footer()}
    <Button onclick={() => staging.close()}>{t('common.cancel')}</Button>
    {#if staging.file && staging.redactable}
      <Button variant={suggestRedact ? 'primary' : 'accent'} icon="redact" onclick={() => staging.redact()}>
        {staging.redacted ? t('staging.redactAgain') : t('staging.redact')}
      </Button>
    {/if}
    <Button
      variant={suggestRedact ? 'accent' : 'primary'}
      icon="upload"
      busy={staging.uploading}
      disabled={!staging.canUpload}
      onclick={() => staging.upload()}
    >
      {suggestRedact ? t('staging.uploadUnredacted') : t('staging.upload')}
    </Button>
  {/snippet}
</Dialog>

<style>
  .stack:global([data-dragging]) .drop,
  .stack:global([data-dragging]) .staged {
    border-color: var(--primary);
    background: var(--primary-subtle);
  }
  .staged {
    border: 1px solid var(--border);
    border-radius: var(--radius-md);
    overflow: hidden;
    transition: background var(--motion);
  }
  .staged img {
    display: block;
    max-width: 100%;
    max-height: 320px;
    margin: 0 auto;
    background: var(--sunken);
  }
  .doc-icon {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: var(--space-2);
    padding: var(--space-6);
    color: var(--fg-muted);
  }
  .meta {
    padding: var(--space-2) var(--space-3);
    border-top: 1px solid var(--border);
  }
  .drop {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: var(--space-1);
    padding: var(--space-6);
    border: 1px dashed var(--border-strong);
    border-radius: var(--radius-md);
    background: var(--surface);
    color: var(--fg);
    cursor: pointer;
    transition: background var(--motion);
  }
  .drop:hover {
    background: var(--hover);
  }
</style>
