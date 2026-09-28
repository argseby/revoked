<script lang="ts">
  import Alert from '../components/Alert.svelte';
  import Button from '../components/Button.svelte';
  import Dialog from '../components/Dialog.svelte';
  import Icon, { type IconName } from '../components/Icon.svelte';
  import TextField from '../components/TextField.svelte';
  import { i18n, t } from '../lib/i18n.svelte';
  import type { MessageKey } from '../lib/locales/en';
  import { serverHost, session } from '../lib/session.svelte';
  import { theme } from '../lib/theme.svelte';
  import HeroDemo from './landing/HeroDemo.svelte';
  import StepArt from './landing/StepArt.svelte';

  let server = $state(session.server);
  let email = $state('');
  let password = $state('');
  let editingServer = $state(false);
  let signingIn = $state(false);

  const custom = $derived(session.canChangeServer && server.replace(/\/+$/, '') !== session.defaultServer);

  const steps: { art: 'store' | 'redact' | 'stamp' | 'revoke'; title: MessageKey; body: MessageKey }[] = [
    { art: 'store', title: 'landing.step1.title', body: 'landing.step1.body' },
    { art: 'redact', title: 'landing.step2.title', body: 'landing.step2.body' },
    { art: 'stamp', title: 'landing.step3.title', body: 'landing.step3.body' },
    { art: 'revoke', title: 'landing.step4.title', body: 'landing.step4.body' },
  ];

  const promises: { icon: IconName; title: MessageKey; body: MessageKey }[] = [
    { icon: 'shield', title: 'landing.trust1.title', body: 'landing.trust1.body' },
    { icon: 'stamp', title: 'landing.trust2.title', body: 'landing.trust2.body' },
    { icon: 'clock', title: 'landing.trust3.title', body: 'landing.trust3.body' },
  ];

  const revokedFeatures: { icon: IconName; title: MessageKey; body: MessageKey }[] = [
    { icon: 'link', title: 'about.live.title', body: 'about.live.body' },
    { icon: 'shield', title: 'about.verified.title', body: 'about.verified.body' },
    { icon: 'folder', title: 'about.host.title', body: 'about.host.body' },
    { icon: 'send', title: 'about.more.title', body: 'about.more.body' },
  ];

  function openSignIn() {
    session.error = null;
    signingIn = true;
  }

  function useDefault() {
    server = session.defaultServer;
    editingServer = false;
  }
</script>

<div class="page">
  <header class="topbar">
    <div class="bar">
      <div class="brand">
        <img class="logo light" src="/revoced-mark-redacted-black-on-white.svg" alt="" />
        <img class="logo dark" src="/revoced-mark-redacted-white-on-black.svg" alt="" />
        <span class="name">{t('brand.name')}<small>{t('brand.by')} <span class="wordmark">Revoked</span></small></span>
      </div>
      <div class="actions">
        <Button small onclick={() => i18n.toggle()} tooltip={t('shell.language')}
          >{i18n.locale === 'de' ? 'EN' : 'DE'}</Button
        >
        <Button small icon={theme.dark ? 'sun' : 'moon'} tooltip={t('shell.theme')} onclick={() => theme.toggle()} />
        <Button small variant="primary" onclick={openSignIn}>{t('login.submit')}</Button>
      </div>
    </div>
  </header>

  <main>
    <section class="hero">
      <div class="copy">
        <p class="eyebrow">{t('landing.eyebrow')}</p>
        <h1>{t('landing.title')}</h1>
        <p class="lead">{t('landing.lead')}</p>
        <ul class="points">
          <li><Icon name="check" /> {t('landing.point1')}</li>
          <li><Icon name="check" /> {t('landing.point2')}</li>
          <li><Icon name="check" /> {t('landing.point3')}</li>
        </ul>
        <div class="ctas">
          <Button variant="primary" onclick={openSignIn}>{t('login.submit')}</Button>
          <a class="ghost" href="#how">{t('landing.how')}</a>
        </div>
      </div>
      <HeroDemo />
    </section>

    <section id="how" class="how">
      <h2>{t('landing.how')}</h2>
      <ol class="steps">
        {#each steps as s, i (s.art)}
          <li class="step">
            <StepArt kind={s.art} />
            <div class="step-copy">
              <span class="num">{i + 1}</span>
              <h3>{t(s.title)}</h3>
              <p class="muted">{t(s.body)}</p>
            </div>
          </li>
        {/each}
      </ol>
    </section>

    <section class="trust">
      {#each promises as p (p.title)}
        <div class="promise">
          <span class="promise-icon"><Icon name={p.icon} size={20} /></span>
          <div>
            <h3>{t(p.title)}</h3>
            <p class="muted small">{t(p.body)}</p>
          </div>
        </div>
      {/each}
    </section>

    <section class="about" aria-labelledby="about-title">
      <div class="about-intro">
        <p class="eyebrow">{t('about.eyebrow')}</p>
        <h2 id="about-title" class="about-mark">
          <img class="logo light" src="/revoced-mark-redacted-black-on-white.svg" alt="" />
          <img class="logo dark" src="/revoced-mark-redacted-white-on-black.svg" alt="" />
          <span class="wordmark">Revoked</span>
        </h2>
        <p class="lead">{t('about.lead')}</p>
        <p class="muted">{t('about.body')}</p>
        <a class="ghost" href="https://revoked.link" target="_blank" rel="noopener noreferrer"
          >{t('about.more')} <span aria-hidden="true">→</span></a
        >
      </div>
      <ul class="about-grid">
        {#each revokedFeatures as f (f.title)}
          <li>
            <span class="promise-icon"><Icon name={f.icon} size={18} /></span>
            <h3>{t(f.title)}</h3>
            <p class="muted small">{t(f.body)}</p>
          </li>
        {/each}
      </ul>
    </section>

  </main>

  <footer class="small muted">
    <span>{t('brand.name')} · {t('brand.by')} <span class="wordmark">Revoked</span></span>
    <span>{t('landing.footer')}</span>
  </footer>
</div>

<Dialog open={signingIn} title={t('landing.signinTitle')} onclose={() => (signingIn = false)}>
  <form
    id="signin-form"
    class="stack"
    onsubmit={(e) => {
      e.preventDefault();
      session.signIn(server, email, password);
    }}
  >
    <p class="muted">{t('landing.signinLead')}</p>
    <TextField label={t('login.email')} type="email" bind:value={email} autocomplete="username" required />
    <TextField
      label={t('login.password')}
      type="password"
      bind:value={password}
      autocomplete="current-password"
      required
    />

    {#if editingServer}
      <div class="stack-sm">
        <TextField
          label={t('login.server')}
          type="url"
          bind:value={server}
          placeholder={session.defaultServer}
          hint={t('login.serverHint')}
        />
        <div class="row">
          <Button small onclick={() => (editingServer = false)}>{t('common.done')}</Button>
          {#if custom}
            <Button small onclick={useDefault}>{t('login.useDefault', { host: serverHost(session.defaultServer) })}</Button>
          {/if}
        </div>
      </div>
    {:else}
      <div class="server-row small">
        <span class="muted">{t('login.server')}:</span>
        <span class="mono">{serverHost(server || session.defaultServer)}</span>
        {#if custom}<span class="custom-tag">{t('login.custom')}</span>{/if}
        {#if session.canChangeServer}
          <button type="button" class="link-btn" onclick={() => (editingServer = true)}>
            <Icon name="pen" size={12} />
            {t('login.change')}
          </button>
        {/if}
      </div>
    {/if}

    {#if session.error}<Alert tone="bad">{session.error}</Alert>{/if}
    <p class="small muted">{t('login.footer')}</p>
  </form>
  {#snippet footer()}
    <Button onclick={() => (signingIn = false)}>{t('common.cancel')}</Button>
    <Button type="submit" form="signin-form" variant="primary" busy={session.busy}>{t('login.submit')}</Button>
  {/snippet}
</Dialog>

<style>
  .page {
    min-height: 100vh;
    display: flex;
    flex-direction: column;
  }
  .topbar {
    position: sticky;
    top: 0;
    z-index: 10;
    background: color-mix(in srgb, var(--surface) 88%, transparent);
    backdrop-filter: blur(8px);
    border-bottom: 1px solid var(--border);
  }
  .bar {
    max-width: 1080px;
    margin: 0 auto;
    padding: var(--space-2) var(--space-4);
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: var(--space-3);
  }
  .brand {
    display: flex;
    align-items: center;
    gap: var(--space-2);
    font-weight: 700;
    font-size: 16px;
    min-width: 0;
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
  .logo {
    width: 28px;
    height: 28px;
    border-radius: var(--radius-sm);
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
  .actions {
    display: flex;
    gap: var(--space-2);
    flex-shrink: 0;
  }

  main {
    flex: 1;
    width: 100%;
    max-width: 1080px;
    margin: 0 auto;
    padding: 0 var(--space-4);
  }
  section {
    padding: var(--space-6) 0;
  }
  h1 {
    font-size: clamp(30px, 5vw, 46px);
    line-height: 1.08;
    letter-spacing: -0.03em;
    font-weight: 750;
  }
  h2 {
    font-size: 26px;
    letter-spacing: -0.02em;
    margin-bottom: var(--space-5);
  }
  h3 {
    font-size: 16px;
    margin-bottom: var(--space-1);
  }

  .hero {
    display: grid;
    gap: var(--space-6);
    align-items: center;
    padding-top: clamp(24px, 6vw, 64px);
  }
  @media (min-width: 900px) {
    .hero {
      grid-template-columns: 1.05fr 1fr;
      gap: 48px;
    }
  }
  .copy {
    display: flex;
    flex-direction: column;
    gap: var(--space-4);
  }
  .eyebrow {
    display: inline-flex;
    align-self: flex-start;
    padding: 4px 12px;
    border-radius: 999px;
    background: var(--primary-subtle);
    color: var(--primary);
    font-size: 12px;
    font-weight: 700;
    letter-spacing: 0.02em;
  }
  .lead {
    font-size: 17px;
    line-height: 1.55;
    color: var(--fg-muted);
    max-width: 34em;
  }
  .points {
    list-style: none;
    padding: 0;
    margin: 0;
    display: flex;
    flex-direction: column;
    gap: var(--space-2);
  }
  .points li {
    display: flex;
    align-items: center;
    gap: var(--space-2);
    font-weight: 550;
  }
  .points :global(svg) {
    color: var(--ok);
    flex-shrink: 0;
  }
  .ctas {
    display: flex;
    align-items: center;
    gap: var(--space-4);
    margin-top: var(--space-2);
  }
  .ghost {
    font-weight: 600;
    text-decoration: none;
  }
  .ghost:hover {
    text-decoration: underline;
  }

  .steps {
    list-style: none;
    padding: 0;
    margin: 0;
    display: grid;
    gap: var(--space-4);
  }
  @media (min-width: 640px) {
    .steps {
      grid-template-columns: repeat(2, 1fr);
    }
  }
  @media (min-width: 1000px) {
    .steps {
      grid-template-columns: repeat(4, 1fr);
    }
  }
  .step {
    display: flex;
    flex-direction: column;
    gap: var(--space-3);
    padding: var(--space-3);
    border: 1px solid var(--border);
    border-radius: var(--radius-lg);
  }
  .step-copy {
    padding: 0 var(--space-1) var(--space-1);
  }
  .num {
    display: inline-grid;
    place-items: center;
    width: 22px;
    height: 22px;
    border-radius: 50%;
    background: var(--primary);
    color: var(--on-primary);
    font-size: 12px;
    font-weight: 700;
    margin-bottom: var(--space-2);
  }

  .trust {
    display: grid;
    gap: var(--space-4);
    border-top: 1px solid var(--border);
    border-bottom: 1px solid var(--border);
  }
  @media (min-width: 800px) {
    .trust {
      grid-template-columns: repeat(3, 1fr);
    }
  }
  .promise {
    display: flex;
    gap: var(--space-3);
  }
  .promise-icon {
    display: grid;
    place-items: center;
    width: 40px;
    height: 40px;
    border-radius: var(--radius-md);
    background: var(--primary-subtle);
    color: var(--primary);
    flex-shrink: 0;
  }

  .about {
    display: grid;
    gap: var(--space-6);
    align-items: start;
    padding: 48px 0 var(--space-6);
  }
  @media (min-width: 900px) {
    .about {
      grid-template-columns: 1fr 1.15fr;
      gap: 48px;
    }
  }
  .about-intro {
    display: flex;
    flex-direction: column;
    gap: var(--space-4);
  }
  .about-mark {
    display: flex;
    align-items: center;
    gap: var(--space-3);
    margin: 0;
    font-size: 36px;
  }
  .about-mark .logo {
    width: 44px;
    height: 44px;
    border-radius: var(--radius-md);
  }
  .about-mark .wordmark {
    font-weight: 800;
  }
  .about-grid {
    list-style: none;
    margin: 0;
    padding: 0;
    display: grid;
    gap: var(--space-4);
  }
  @media (min-width: 560px) {
    .about-grid {
      grid-template-columns: repeat(2, 1fr);
    }
  }
  .about-grid li {
    display: flex;
    flex-direction: column;
    gap: var(--space-2);
    padding: var(--space-4);
    border: 1px solid var(--border);
    border-radius: var(--radius-lg);
  }
  .about-grid h3 {
    margin: 0;
  }

  .server-row {
    display: flex;
    align-items: center;
    flex-wrap: wrap;
    gap: var(--space-2);
  }
  .custom-tag {
    padding: 1px 6px;
    border-radius: var(--radius-sm);
    background: var(--warn-subtle);
    color: var(--warn);
    font-weight: 600;
  }
  .link-btn {
    display: inline-flex;
    align-items: center;
    gap: 4px;
    margin-left: auto;
    padding: 2px 6px;
    border: 0;
    border-radius: var(--radius-sm);
    background: none;
    color: var(--primary);
    font-weight: 600;
    cursor: pointer;
  }
  .link-btn:hover {
    background: var(--hover);
  }

  footer {
    max-width: 1080px;
    width: 100%;
    margin: 0 auto;
    padding: var(--space-5) var(--space-4) var(--space-6);
    display: flex;
    justify-content: space-between;
    flex-wrap: wrap;
    gap: var(--space-2);
    border-top: 1px solid var(--border);
  }

  @media (max-width: 480px) {
    .name small {
      display: none;
    }
  }
</style>
