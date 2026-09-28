<script lang="ts">
  import { untrack } from 'svelte';
  import Button from './components/Button.svelte';
  import Card from './components/Card.svelte';
  import ConfirmDialog from './components/ConfirmDialog.svelte';
  import Icon, { type IconName } from './components/Icon.svelte';
  import Spinner from './components/Spinner.svelte';
  import Toast from './components/Toast.svelte';
  import type { MessageKey } from './lib/locales/en';
  import { applications } from './lib/applications.svelte';
  import { i18n, t } from './lib/i18n.svelte';
  import { profile } from './lib/profile.svelte';
  import { session } from './lib/session.svelte';
  import { theme } from './lib/theme.svelte';
  import { vault } from './lib/vault.svelte';
  import ApplicationsView from './views/ApplicationsView.svelte';
  import DocumentsView from './views/DocumentsView.svelte';
  import Landing from './views/Landing.svelte';
  import ProfileView from './views/ProfileView.svelte';

  type Tab = 'applications' | 'documents' | 'profile';
  const tabs: { id: Tab; label: MessageKey; icon: IconName }[] = [
    { id: 'applications', label: 'nav.applications', icon: 'send' },
    { id: 'documents', label: 'nav.documents', icon: 'folder' },
    { id: 'profile', label: 'nav.profile', icon: 'user' },
  ];

  function fromHash(): Tab {
    const h = window.location.hash.replace(/^#\/?/, '');
    return tabs.some((t) => t.id === h) ? (h as Tab) : 'applications';
  }

  let tab = $state<Tab>(fromHash());

  $effect(() => {
    document.title = t('app.title');
  });

  session.init();

  // Keyed on the workspace, not the user object, which a token refresh replaces.
  const workspace = $derived(session.user ? session.workspace : '');

  $effect(() => {
    if (!workspace) {
      vault.reset();
      applications.reset();
      return;
    }
    untrack(() => {
      vault.load().then(() => profile.fromVault());
      applications.load();
    });
  });

  // "Opened 2×" is only worth something if it is current when you look.
  function refresh() {
    if (session.user && document.visibilityState === 'visible') applications.load();
  }
</script>

<!-- A file dropped outside a drop zone would otherwise open in this tab. -->
<svelte:window
  onhashchange={() => (tab = fromHash())}
  ondragover={(e) => e.preventDefault()}
  ondrop={(e) => e.preventDefault()}
/>
<svelte:document onvisibilitychange={refresh} />

{#if !session.ready}
  <div class="boot"><Spinner large /></div>
{:else if !session.user}
  <Landing />
{:else}
  <header>
    <div class="bar">
      <div class="brand">
        <img class="logo light" src="/revoced-mark-redacted-black-on-white.svg" alt="" />
        <img class="logo dark" src="/revoced-mark-redacted-white-on-black.svg" alt="" />
        <span class="name">{t('brand.name')}<small>{t('brand.by')} <span class="wordmark">Revoked</span></small></span>
      </div>
      <nav aria-label={t('nav.sections')}>
        {#each tabs as item (item.id)}
          <a href="#/{item.id}" class:on={tab === item.id} aria-current={tab === item.id ? 'page' : undefined}>
            <Icon name={item.icon} />
            <span>{t(item.label)}</span>
          </a>
        {/each}
      </nav>
      <div class="row end">
        <Button small onclick={() => i18n.toggle()} tooltip={t('shell.language')}>{i18n.locale === 'de' ? 'EN' : 'DE'}</Button>
        <Button icon={theme.dark ? 'sun' : 'moon'} tooltip={t('shell.theme')} onclick={() => theme.toggle()} />
        <Button icon="logout" tooltip={t('shell.signOut', { email: session.user.email })} onclick={() => session.signOut()} />
      </div>
    </div>
  </header>

  <main>
    {#if !session.workspace}
      <Card>
        <div class="stack-sm">
          <h1 class="header">{t('shell.noWorkspace.title')}</h1>
          <p class="muted">{t('shell.noWorkspace.body')}</p>
          <div><Button icon="refresh" onclick={() => session.refresh()}>{t('shell.noWorkspace.retry')}</Button></div>
        </div>
      </Card>
    {:else if tab === 'applications'}
      <ApplicationsView />
    {:else if tab === 'documents'}
      <DocumentsView />
    {:else}
      <ProfileView />
    {/if}
  </main>
{/if}

<ConfirmDialog />
<Toast />

<style>
  .boot {
    display: grid;
    place-items: center;
    min-height: 100vh;
  }
  header {
    position: sticky;
    top: 0;
    z-index: 10;
    background: var(--surface);
    border-bottom: 1px solid var(--border);
  }
  .bar {
    max-width: 800px;
    margin: 0 auto;
    padding: var(--space-2) var(--space-4);
    display: grid;
    grid-template-columns: auto 1fr auto;
    align-items: center;
    gap: var(--space-4);
  }
  .brand {
    display: flex;
    align-items: center;
    gap: var(--space-2);
    font-weight: 700;
    font-size: 16px;
  }
  .logo {
    width: 28px;
    height: 28px;
    border-radius: var(--radius-sm);
  }
  .name {
    display: flex;
    flex-direction: column;
    line-height: 1.15;
  }
  .name small {
    font-size: 11px;
    font-weight: 500;
    color: var(--fg-muted);
  }
  .logo.dark {
    display: none;
  }
  @media (prefers-color-scheme: dark) {
    :global(:root:not([data-theme='light'])) .logo.light {
      display: none;
    }
    :global(:root:not([data-theme='light'])) .logo.dark {
      display: block;
    }
  }
  :global(:root[data-theme='dark']) .logo.light {
    display: none;
  }
  :global(:root[data-theme='dark']) .logo.dark {
    display: block;
  }
  nav {
    display: flex;
    gap: var(--space-1);
    justify-content: center;
  }
  nav a {
    display: inline-flex;
    align-items: center;
    gap: var(--space-2);
    padding: var(--space-2) var(--space-3);
    border-radius: var(--radius-md);
    color: var(--fg-muted);
    text-decoration: none;
    font-weight: 550;
  }
  nav a:hover {
    background: var(--hover);
  }
  nav a.on {
    background: var(--primary-subtle);
    color: var(--primary);
  }
  .end {
    justify-content: flex-end;
    flex-wrap: nowrap;
  }
  main {
    max-width: 800px;
    margin: 0 auto;
    padding: var(--space-6) var(--space-4) calc(var(--space-6) * 3);
  }

  /* On a phone the sections move to a bottom bar, where a thumb reaches them. */
  @media (max-width: 640px) {
    .name small {
      display: none;
    }
    nav {
      position: fixed;
      left: 0;
      right: 0;
      bottom: 0;
      background: var(--surface);
      border-top: 1px solid var(--border);
      padding: var(--space-2) var(--space-2) calc(var(--space-2) + env(safe-area-inset-bottom));
      justify-content: space-around;
    }
    nav a {
      flex-direction: column;
      gap: 2px;
      font-size: 12px;
      flex: 1;
    }
  }
</style>
