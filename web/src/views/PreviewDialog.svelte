<script lang="ts">
  import Alert from '../components/Alert.svelte';
  import Button from '../components/Button.svelte';
  import Dialog from '../components/Dialog.svelte';
  import Spinner from '../components/Spinner.svelte';
  import { t } from '../lib/i18n.svelte';
  import { preview } from '../lib/staging.svelte';
</script>

<Dialog open={!!preview.record} wide title={preview.record?.label ?? ''} onclose={() => preview.close()}>
  {#if preview.loading}
    <div class="center"><Spinner large /></div>
  {:else if preview.error}
    <Alert tone="bad">{preview.error}</Alert>
  {:else if preview.url && preview.mime.startsWith('image/')}
    <img src={preview.url} alt={preview.record?.filename ?? ''} />
  {:else if preview.url && preview.mime === 'application/pdf'}
    <iframe src={preview.url} title={preview.record?.filename ?? ''}></iframe>
  {:else}
    <p class="muted">{t('preview.none')}</p>
  {/if}
  <p class="small muted note">{t('preview.note')}</p>
  {#snippet footer()}
    {#if preview.url}
      <a class="save" href={preview.url} download={preview.record?.filename ?? 'document'}>{t('common.save')}</a>
    {/if}
    <Button variant="primary" onclick={() => preview.close()}>{t('common.close')}</Button>
  {/snippet}
</Dialog>

<style>
  .center {
    display: grid;
    place-items: center;
    min-height: 200px;
  }
  img {
    display: block;
    max-width: 100%;
    margin: 0 auto;
  }
  iframe {
    width: 100%;
    height: 65vh;
    border: 0;
  }
  .note {
    margin-top: var(--space-3);
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
