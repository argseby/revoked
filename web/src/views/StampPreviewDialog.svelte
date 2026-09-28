<script lang="ts">
  import Alert from '../components/Alert.svelte';
  import Button from '../components/Button.svelte';
  import Dialog from '../components/Dialog.svelte';
  import Segmented from '../components/Segmented.svelte';
  import Spinner from '../components/Spinner.svelte';
  import { t } from '../lib/i18n.svelte';
  import { recordName } from '../lib/record-name';
  import { stampPreview } from '../lib/stamp-preview.svelte';
  import { stem } from '../lib/filename';

  const options = $derived(stampPreview.files.map((f, i) => ({ value: i, label: recordName(f) })));
  let picked = $state(0);

  $effect(() => {
    if (picked !== stampPreview.index && stampPreview.open) void stampPreview.select(picked);
  });
  $effect(() => {
    if (!stampPreview.open) picked = 0;
  });

  const saveName = $derived(
    `${stem(stampPreview.file?.filename ?? 'document')}-preview${stampPreview.mime === 'application/pdf' ? '.pdf' : stampPreview.mime === 'image/jpeg' ? '.jpg' : '.png'}`,
  );
</script>

<Dialog open={stampPreview.open} wide title={t('stampPreview.title')} onclose={() => stampPreview.close()}>
  <div class="stack">
    {#if options.length > 1}
      <div class="picker"><Segmented label={t('stampPreview.pick')} {options} bind:value={picked} /></div>
    {/if}
    <div class="frame">
      {#if stampPreview.loading}
        <Spinner large />
      {:else if stampPreview.error}
        <Alert tone="bad">{stampPreview.error}</Alert>
      {:else if stampPreview.url && stampPreview.mime === 'application/pdf'}
        <iframe src={stampPreview.url} title={stampPreview.file?.label ?? ''}></iframe>
      {:else if stampPreview.url}
        <img src={stampPreview.url} alt={stampPreview.file?.label ?? ''} />
      {/if}
    </div>
    <p class="small muted">
      {t(stampPreview.source && 'link' in stampPreview.source ? 'stampPreview.noteLink' : 'stampPreview.note')}
    </p>
  </div>
  {#snippet footer()}
    {#if stampPreview.url}
      <a class="save" href={stampPreview.url} download={saveName}>{t('stampPreview.save')}</a>
    {/if}
    <Button variant="primary" onclick={() => stampPreview.close()}>{t('common.close')}</Button>
  {/snippet}
</Dialog>

<style>
  .picker {
    overflow-x: auto;
  }
  .frame {
    display: grid;
    place-items: center;
    min-height: 240px;
    background: var(--sunken);
    border-radius: var(--radius-md);
    overflow: hidden;
  }
  img {
    display: block;
    max-width: 100%;
    max-height: 65vh;
  }
  iframe {
    width: 100%;
    height: 65vh;
    border: 0;
  }
  .save {
    display: inline-flex;
    align-items: center;
    min-height: 36px;
    padding: 0 var(--space-4);
    border: 1px solid var(--border);
    border-radius: var(--radius-md);
    color: var(--fg);
    font-weight: 550;
    text-decoration: none;
  }
  .save:hover {
    background: var(--hover);
  }
</style>
