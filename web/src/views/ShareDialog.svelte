<script lang="ts">
  import Alert from '../components/Alert.svelte';
  import Button from '../components/Button.svelte';
  import Dialog from '../components/Dialog.svelte';
  import QrCode from '../components/QrCode.svelte';
  import { addressOf, applications, type Link } from '../lib/applications.svelte';
  import { copyText } from '../lib/confirm.svelte';
  import { t } from '../lib/i18n.svelte';

  let { link, fresh = false, onclose }: { link: Link | null; fresh?: boolean; onclose: () => void } = $props();

  const target = $derived(link ? applications.urlFor(link) : null);
</script>

<Dialog open={!!link} title={fresh ? t('share.ready') : link ? addressOf(link) : ''} {onclose}>
  {#if link && target}
    <div class="stack center">
      {#if fresh}
        <p>{t('share.send')} <strong>{addressOf(link)}</strong>. {t('share.sendTail')}</p>
      {/if}
      <QrCode text={target.url} />
      <input class="url mono small" readonly value={target.url} onfocus={(e) => e.currentTarget.select()} />
      {#if !target.reachable}
        <Alert tone="warn">{t('share.local')}</Alert>
      {/if}
    </div>
  {/if}
  {#snippet footer()}
    <Button onclick={onclose}>{t('common.done')}</Button>
    <Button variant="primary" icon="copy" onclick={() => target && copyText(target.url, t('apps.linkCopied'))}
      >{t('apps.copyLink')}</Button
    >
  {/snippet}
</Dialog>

<style>
  .center {
    align-items: center;
    text-align: center;
  }
  .url {
    width: 100%;
    padding: var(--space-2) var(--space-3);
    border: 1px solid var(--border);
    border-radius: var(--radius-md);
    background: var(--sunken);
    text-align: center;
  }
</style>
