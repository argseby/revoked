<script lang="ts">
  import Badge from '../components/Badge.svelte';
  import Button from '../components/Button.svelte';
  import Card from '../components/Card.svelte';
  import { addressOf, applications, extendDays, watermarkTag, type Link } from '../lib/applications.svelte';
  import { confirm, copyText } from '../lib/confirm.svelte';
  import { daysUntil } from '../lib/format';
  import { formatDate, t } from '../lib/i18n.svelte';
  import { stampPreview } from '../lib/stamp-preview.svelte';

  let { link, onshare, onedit }: { link: Link; onshare: (l: Link) => void; onedit: (l: Link) => void } = $props();

  const busy = $derived(applications.isBusy(link.id));
  const live = $derived(link.status === 'active' || link.status === 'paused');
  const left = $derived(link.expiresAt ? daysUntil(link.expiresAt) : null);
  const files = $derived(applications.filesOf(link));

  const status = $derived.by(() => {
    switch (link.status) {
      case 'active':
        return { text: t('apps.status.active'), tone: 'ok' as const };
      case 'paused':
        return { text: t('apps.status.paused'), tone: 'warn' as const };
      case 'expired':
        return { text: t('apps.status.expired'), tone: 'neutral' as const };
      default:
        return { text: t('apps.status.revoked'), tone: 'bad' as const };
    }
  });

  const expiry = $derived.by(() => {
    if (!link.expiresAt || !live || left === null) return null;
    return left <= 1 ? t('apps.expiresToday') : t('apps.expiresIn', { n: left });
  });

  async function revoke() {
    const ok = await confirm.ask({
      title: t('apps.revoke.title'),
      message: t('apps.revoke.message', { address: addressOf(link) }),
      action: t('apps.revoke'),
      destructive: true,
    });
    if (ok) await applications.revoke(link);
  }

  async function remove() {
    const ok = await confirm.ask({
      title: t('apps.delete.title'),
      message: t('apps.delete.message'),
      action: t('common.delete'),
      destructive: true,
    });
    if (ok) await applications.remove(link);
  }
</script>

<Card>
  <div class="stack-sm">
    <div class="spread top">
      <h3 class="title address">{addressOf(link)}</h3>
      <span class="small muted">{formatDate(link.created)}</span>
    </div>
    <div class="row">
      <Badge tone={status.tone} text={status.text} />
      <Badge
        icon="eye"
        tone={link.viewCount > 0 ? 'primary' : 'neutral'}
        text={link.viewCount > 0 ? t('apps.opened', { n: link.viewCount }) : t('apps.notOpened')}
      />
      {#if expiry}<Badge icon="clock" tone={left !== null && left <= 2 ? 'warn' : 'neutral'} text={expiry} />{/if}
      <Badge icon="stamp" text="#{watermarkTag(link)}" title={t('apps.tagTitle')} />
      <span class="small muted">{t('common.items', { n: link.records.length })}</span>
    </div>
  </div>
  {#snippet actions()}
    {#if live}
      <Button
        small
        variant="primary"
        icon="copy"
        onclick={() => copyText(applications.urlFor(link).url, t('apps.linkCopied'))}>{t('apps.copyLink')}</Button
      >
      <Button small icon="qr" onclick={() => onshare(link)}>{t('apps.qr')}</Button>
    {/if}
    {#if files.length}
      <Button small icon="eye" onclick={() => stampPreview.show(files, { link: link.id })}>{t('apps.preview')}</Button>
      <Button small icon="download" busy={busy} onclick={() => applications.download(link)}>{t('apps.download')}</Button>
    {/if}
    {#if link.status !== 'revoked'}
      <Button small icon="pen" onclick={() => onedit(link)}>{t('apps.edit')}</Button>
      <Button small icon="clock" busy={busy} onclick={() => applications.extend(link)}
        >{t('apps.extend', { n: extendDays })}</Button
      >
    {/if}
    {#if live}
      <Button small variant="destructive" icon="revoke" onclick={revoke}>{t('apps.revoke')}</Button>
    {/if}
    <Button small variant="destructive" icon="trash" onclick={remove}>{t('common.delete')}</Button>
  {/snippet}
</Card>

<style>
  .top {
    align-items: baseline;
  }
  .address {
    overflow-wrap: anywhere;
  }
</style>
