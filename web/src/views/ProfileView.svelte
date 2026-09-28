<script lang="ts">
  import Alert from '../components/Alert.svelte';
  import Button from '../components/Button.svelte';
  import Card from '../components/Card.svelte';
  import Dialog from '../components/Dialog.svelte';
  import Segmented from '../components/Segmented.svelte';
  import TextField from '../components/TextField.svelte';
  import { confirm } from '../lib/confirm.svelte';
  import { t } from '../lib/i18n.svelte';
  import { profile, type CustomType, type EditableField } from '../lib/profile.svelte';
  import { staging } from '../lib/staging.svelte';
  import { vault, type VaultRecord } from '../lib/vault.svelte';
  import DocumentCard from './DocumentCard.svelte';
  import FileDialogs from './FileDialogs.svelte';

  const inputType = { text: 'text', number: 'number', datetime: 'date' } as const;
  const autofill: Record<string, AutoFill> = {
    full_name: 'name',
    email: 'email',
    phone: 'tel',
    current_address: 'street-address',
    employer: 'organization',
  };
  const types = $derived<{ value: CustomType; label: string }[]>([
    { value: 'text', label: t('type.text') },
    { value: 'number', label: t('type.number') },
    { value: 'datetime', label: t('type.datetime') },
    { value: 'file', label: t('type.file') },
  ]);

  function add() {
    const field = profile.addField();
    if (field?.type === 'file') staging.begin({ key: field.key, label: field.label });
  }

  async function remove(f: { key: string; label: string }) {
    const hasRecord = vault.byKey.has(f.key);
    const ok =
      !hasRecord ||
      (await confirm.ask({
        title: t('profile.custom.remove.title', { label: f.label }),
        message: t('profile.custom.remove.message'),
        action: t('common.delete'),
        destructive: true,
      }));
    if (ok) await profile.remove(f);
  }

  async function redactExisting(r: VaultRecord) {
    const ok = await confirm.ask({
      title: t('docs.redactExisting.title'),
      message: t('docs.redactExisting.message'),
      action: t('common.continue'),
    });
    if (ok) await staging.redactExisting(r);
  }
</script>

{#snippet field(f: EditableField)}
  <div class="field" class:custom={f.custom}>
    <TextField
      label={f.label}
      type={inputType[f.type]}
      autocomplete={autofill[f.key]}
      bind:value={profile.values[f.key]}
      maxlength={1000}
    />
    {#if f.custom}
      <span class="remove">
        <Button
          small
          icon="trash"
          variant="destructive"
          tooltip={t('profile.custom.remove', { label: f.label })}
          onclick={() => remove(f)}
        />
      </span>
    {/if}
  </div>
{/snippet}

<form
  class="stack"
  onsubmit={(e) => {
    e.preventDefault();
    profile.save();
  }}
>
  <div class="stack-sm">
    <h1 class="header">{t('profile.title')}</h1>
    <p class="muted">{t('profile.intro')}</p>
  </div>

  <Card>
    <div class="grid">
      {#each profile.standard as f (f.key)}{@render field(f)}{/each}
    </div>
  </Card>

  <Card>
    <div class="stack-sm">
      <div class="spread">
        <h2 class="title">{t('profile.custom.title')}</h2>
        <Button small icon="plus" onclick={() => profile.openDialog()}>{t('profile.custom.add')}</Button>
      </div>
      <p class="small muted">{t('profile.custom.intro')}</p>
      {#if profile.custom.length}
        <div class="grid">
          {#each profile.custom as f (f.key)}{@render field(f)}{/each}
        </div>
      {:else if !profile.customFiles.length}
        <p class="small muted empty">{t('profile.custom.empty')}</p>
      {/if}
    </div>
  </Card>

  {#each profile.customFiles as r (r.id)}
    <DocumentCard
      target={{ key: r.key, label: r.label || r.key }}
      record={r}
      onredactexisting={redactExisting}
      ondelete={(rec) => remove({ key: rec.key, label: rec.label || rec.key })}
    />
  {/each}

  <div class="savebar">
    <span class="small muted">
      {#if profile.dirty}{t('profile.unsaved')}{:else if vault.loaded}{t('profile.saved')}{/if}
    </span>
    <Button type="submit" variant="primary" icon="check" busy={profile.saving} disabled={!profile.dirty}
      >{t('common.save')}</Button
    >
  </div>

  {#if profile.error}<Alert tone="bad">{profile.error}</Alert>{/if}
</form>

<Dialog open={profile.dialogOpen} title={t('profile.custom.dialog')} onclose={() => (profile.dialogOpen = false)}>
  <form
    class="stack"
    onsubmit={(e) => {
      e.preventDefault();
      add();
    }}
  >
    <TextField
      label={t('profile.custom.name')}
      placeholder={t('profile.custom.namePlaceholder')}
      bind:value={profile.newLabel}
      maxlength={80}
      error={profile.labelTaken ? t('profile.custom.exists') : null}
    />
    <div class="stack-sm">
      <span class="label">{t('profile.custom.type')}</span>
      <div class="types"><Segmented label={t('profile.custom.type')} options={types} bind:value={profile.newType} /></div>
    </div>
  </form>
  {#snippet footer()}
    <Button onclick={() => (profile.dialogOpen = false)}>{t('common.cancel')}</Button>
    <Button variant="primary" icon="plus" disabled={!profile.newLabel.trim() || profile.labelTaken} onclick={add}
      >{t('profile.custom.add')}</Button
    >
  {/snippet}
</Dialog>

<FileDialogs />

<style>
  .grid {
    display: grid;
    gap: var(--space-4);
    grid-template-columns: 1fr;
  }
  @media (min-width: 640px) {
    .grid {
      grid-template-columns: 1fr 1fr;
    }
  }
  .field.custom {
    display: flex;
    align-items: flex-end;
    gap: var(--space-2);
  }
  .field.custom > :global(:first-child) {
    flex: 1;
    min-width: 0;
  }
  /* Centred on the input beside it (40px) rather than on the input plus its
     label: a small button is 30px tall. */
  .remove {
    display: flex;
    margin-bottom: 5px;
  }
  .empty {
    padding-top: var(--space-2);
  }
  .label {
    font-size: 12px;
    font-weight: 600;
    color: var(--fg-muted);
  }
  .types {
    overflow-x: auto;
  }
  .savebar {
    position: sticky;
    bottom: var(--space-4);
    display: flex;
    align-items: center;
    justify-content: flex-end;
    gap: var(--space-3);
    padding: var(--space-3) var(--space-4);
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: var(--radius-lg);
  }
  @media (max-width: 640px) {
    .savebar {
      bottom: calc(76px + env(safe-area-inset-bottom));
    }
  }
</style>
