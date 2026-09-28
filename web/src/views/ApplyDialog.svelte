<script lang="ts">
  import Alert from '../components/Alert.svelte';
  import Badge from '../components/Badge.svelte';
  import Button from '../components/Button.svelte';
  import CheckRow from '../components/CheckRow.svelte';
  import Dialog from '../components/Dialog.svelte';
  import Segmented from '../components/Segmented.svelte';
  import TextField from '../components/TextField.svelte';
  import { applications, expiryChoices, maxAddress, stampText } from '../lib/applications.svelte';
  import { formatBytes } from '../lib/format';
  import { formatDate, t } from '../lib/i18n.svelte';
  import { stampPreview } from '../lib/stamp-preview.svelte';
  import { recordName as name } from '../lib/record-name';
  import { isProfileRecord } from '../lib/tenant';
  import { isStampable, vault } from '../lib/vault.svelte';

  let {
    open,
    onclose,
    ondone,
  }: { open: boolean; onclose: () => void; ondone: (id: string, created: boolean) => void } = $props();

  const editing = $derived(applications.editing);
  const expiryOptions = $derived([
    ...(editing
      ? [{ value: 0, label: editing.expiresAt ? t('apply.keepExpiry', { date: formatDate(editing.expiresAt) }) : t('apply.keep') }]
      : []),
    ...expiryChoices.map((d) => ({ value: d as number, label: t('apply.days', { n: d }) })),
  ]);

  const files = $derived(vault.files);
  const details = $derived(vault.records.filter((r) => r.type !== 'file' && isProfileRecord(r.key)));
  const previewable = $derived(files.filter((r) => applications.selected.has(r.id) && isStampable(r)));
  const today = new Intl.DateTimeFormat('sv-SE').format(new Date());

  async function submit() {
    const created = !editing;
    const link = await applications.save();
    if (link) ondone(link.id, created);
  }
</script>

<Dialog {open} wide title={editing ? t('apply.editTitle') : t('apply.title')} {onclose}>
  <form
    class="stack"
    onsubmit={(e) => {
      e.preventDefault();
      submit();
    }}
  >
    <TextField
      label={t('apply.address')}
      placeholder={t('apply.addressPlaceholder')}
      bind:value={applications.address}
      maxlength={maxAddress}
      hint={t('apply.addressHint')}
      required
    />

    <div class="stamp spread">
      <div class="stack-sm grow">
        <span class="small muted">{t('apply.stamp')}</span>
        <span class="mono small">{stampText(applications.address || '…')} · {today} · #……</span>
        {#if !previewable.length}<span class="small muted">{t('apply.previewStampHint')}</span>{/if}
      </div>
      {#if previewable.length}
        <Button
          small
          icon="eye"
          onclick={() => stampPreview.show(previewable, { text: stampText(applications.address || '…') })}
          >{t('apply.previewStamp')}</Button
        >
      {/if}
    </div>

    <fieldset>
      <legend class="title">{t('apply.documents')}</legend>
      {#if files.length === 0}
        <p class="small muted">{t('apply.noDocuments')}</p>
      {/if}
      {#each files as r (r.id)}
        <CheckRow checked={applications.selected.has(r.id)} onchange={() => applications.toggle(r.id)}>
          <span class="name">{name(r)}</span>
          <span class="small muted">{r.filename} · {formatBytes(r.size ?? 0)}</span>
          {#snippet trailing()}
            {#if !isStampable(r)}<Badge tone="warn" text={t('apply.cantStamp')} />{/if}
          {/snippet}
        </CheckRow>
      {/each}
    </fieldset>

    {#if details.length}
      <fieldset>
        <legend class="title">{t('apply.details')}</legend>
        {#each details as r (r.id)}
          <CheckRow checked={applications.selected.has(r.id)} onchange={() => applications.toggle(r.id)}>
            <span class="name">{name(r)}</span>
            <span class="small muted">{r.value}</span>
          </CheckRow>
        {/each}
      </fieldset>
    {/if}

    {#if applications.unstampable.length}
      <Alert tone="warn">
        {t('apply.unstampable', {
          names: applications.unstampable.map(name).join(', '),
          n: applications.unstampable.length,
        })}
      </Alert>
    {/if}

    <div class="spread">
      <span class="title">{t('apply.expires')}</span>
      <Segmented label={t('apply.expires')} options={expiryOptions} bind:value={applications.expiryDays} />
    </div>

    {#if applications.identity || editing?.identity}
      <CheckRow checked={applications.signed} onchange={() => (applications.signed = !applications.signed)}>
        <span class="name"
          >{applications.identity && (!editing?.identity || editing.identity === applications.identity.id)
            ? t('apply.sign', { name: applications.identity.name })
            : t('apply.signKeep')}</span
        >
        <span class="small muted">{t('apply.signHint')}</span>
      </CheckRow>
    {/if}

    {#if editing}<p class="small muted">{t('apply.editNote')}</p>{/if}
    {#if applications.draftError}<Alert tone="bad">{applications.draftError}</Alert>{/if}
  </form>

  {#snippet footer()}
    <Button onclick={onclose}>{t('common.cancel')}</Button>
    <Button
      variant="primary"
      icon={editing ? 'check' : 'link'}
      busy={applications.submitting}
      disabled={!applications.canSubmit}
      onclick={submit}>{editing ? t('apply.saveChanges') : t('apply.create')}</Button
    >
  {/snippet}
</Dialog>

<style>
  fieldset {
    border: 1px solid var(--border);
    border-radius: var(--radius-md);
    padding: var(--space-2) var(--space-1);
    margin: 0;
    display: flex;
    flex-direction: column;
  }
  legend {
    padding: 0 var(--space-2);
  }
  fieldset > p {
    padding: var(--space-2) var(--space-3);
  }
  .name {
    display: block;
    font-weight: 550;
  }
  .name + span {
    display: block;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .stamp {
    padding: var(--space-3);
    background: var(--sunken);
    border-radius: var(--radius-md);
  }
  .grow {
    flex: 1;
    min-width: 0;
    gap: var(--space-1);
  }
</style>
