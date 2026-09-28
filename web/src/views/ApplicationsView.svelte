<script lang="ts">
  import Alert from '../components/Alert.svelte';
  import Button from '../components/Button.svelte';
  import Card from '../components/Card.svelte';
  import Spinner from '../components/Spinner.svelte';
  import { applications, type Link } from '../lib/applications.svelte';
  import { toast } from '../lib/confirm.svelte';
  import { t } from '../lib/i18n.svelte';
  import { vault } from '../lib/vault.svelte';
  import ApplicationCard from './ApplicationCard.svelte';
  import ApplyDialog from './ApplyDialog.svelte';
  import ShareDialog from './ShareDialog.svelte';
  import StampPreviewDialog from './StampPreviewDialog.svelte';

  let applying = $state(false);
  let sharing = $state<Link | null>(null);
  let fresh = $state(false);

  function start() {
    applications.startDraft();
    applying = true;
  }

  function edit(l: Link) {
    applications.startEdit(l);
    applying = true;
  }

  function done(id: string, created: boolean) {
    applying = false;
    if (!created) {
      toast.show(t('apply.saved'));
      return;
    }
    fresh = true;
    sharing = applications.links.find((l) => l.id === id) ?? null;
  }

  function share(l: Link) {
    fresh = false;
    sharing = l;
  }

  const live = $derived(applications.links.filter((l) => l.status === 'active' || l.status === 'paused'));
  const past = $derived(applications.links.filter((l) => l.status !== 'active' && l.status !== 'paused'));
</script>

<div class="stack">
  <div class="spread">
    <div class="stack-sm intro">
      <h1 class="header">{t('apps.title')}</h1>
      <p class="muted">{t('apps.intro')}</p>
    </div>
    <Button variant="primary" icon="plus" disabled={!vault.loaded} onclick={start}>{t('apps.new')}</Button>
  </div>

  {#if applications.error}<Alert tone="bad">{applications.error}</Alert>{/if}

  {#if !applications.loaded && applications.loading}
    <div class="center"><Spinner large /></div>
  {:else if applications.loaded && applications.links.length === 0}
    <Card>
      <div class="empty stack-sm">
        <p class="title">{t('apps.empty.title')}</p>
        <p class="muted">{t('apps.empty.body')}</p>
      </div>
    </Card>
  {:else}
    {#each live as link (link.id)}
      <ApplicationCard {link} onshare={share} onedit={edit} />
    {/each}
    {#if past.length}
      <h2 class="title section">{t('apps.ended')}</h2>
      {#each past as link (link.id)}
        <ApplicationCard {link} onshare={share} onedit={edit} />
      {/each}
    {/if}
  {/if}
</div>

<ApplyDialog open={applying} onclose={() => (applying = false)} ondone={done} />
<ShareDialog link={sharing} {fresh} onclose={() => (sharing = null)} />
<StampPreviewDialog />

<style>
  .intro {
    max-width: 520px;
  }
  .center {
    display: grid;
    place-items: center;
    padding: var(--space-6);
  }
  .empty {
    text-align: center;
    padding: var(--space-4);
  }
  .section {
    margin-top: var(--space-2);
  }
</style>
