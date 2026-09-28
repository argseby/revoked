<script lang="ts">
  import Icon from '../../components/Icon.svelte';
  import { t } from '../../lib/i18n.svelte';

  // One 12-second story on a single clock: every element below runs a
  // keyframe of the same length, so the captions stay in step with the
  // picture. With reduced motion the finished state is shown instead.
  const steps = ['demo.step.blackout', 'demo.step.stamp', 'demo.step.send', 'demo.step.revoke'] as const;
</script>

<figure class="demo" aria-label={t('demo.label')}>
  <div class="stage" aria-hidden="true">
    <div class="doc">
      <div class="doc-head">
        <span class="doc-title">{t('demo.doc')}</span>
        <span class="doc-sub">Lena Muster · 08/2026</span>
      </div>
      <div class="rows">
        <div class="row"><span>{t('demo.gross')}</span><span class="num">4.850,00</span></div>
        <div class="row"><span>{t('demo.net')}</span><span class="num">3.200,00</span></div>
        <div class="row redact">
          <span>IBAN</span>
          <span class="num masked">DE89 3704 0044 0532 01<span class="bar"></span></span>
        </div>
        <div class="row redact">
          <span>{t('demo.taxId')}</span>
          <span class="num masked">12 345 678 901<span class="bar late"></span></span>
        </div>
        <div class="line w90"></div>
        <div class="line w70"></div>
        <div class="line w80"></div>
      </div>
      <div class="stamp">
        {#each Array(7) as _, i (i)}
          <span>Nur für Wohnungsbewerbung Musterstr. 5 · 2026-09-28 · #a3f9c1</span>
        {/each}
      </div>
    </div>

    <div class="chip link">
      <Icon name="link" size={14} />
      <span class="url">revoked.link/s/k3f9x2…</span>
      <span class="copied">{t('demo.copied')}</span>
    </div>
    <div class="chip opened"><Icon name="eye" size={14} /> {t('demo.opened')}</div>
    <div class="chip revoked"><Icon name="revoke" size={14} /> {t('demo.revoked')}</div>
  </div>

  <figcaption>
    <ol class="timeline">
      {#each steps as s, i (s)}
        <li class="s{i + 1}"><span class="dot">{i + 1}</span>{t(s)}</li>
      {/each}
    </ol>
  </figcaption>
</figure>

<style>
  .demo {
    --loop: 12s;
    margin: 0;
    display: flex;
    flex-direction: column;
    gap: var(--space-4);
  }
  .stage {
    position: relative;
    height: 360px;
    border-radius: var(--radius-lg);
    background:
      radial-gradient(120% 90% at 80% 0%, var(--primary-subtle) 0%, transparent 60%),
      var(--sunken);
    overflow: hidden;
  }

  /* The document is paper in both themes: it stands for a file, not UI. */
  .doc {
    position: absolute;
    left: 50%;
    top: 28px;
    width: min(300px, 78%);
    height: 290px;
    margin-left: calc(min(300px, 78%) / -2);
    padding: 18px 20px;
    border-radius: 10px;
    background: #ffffff;
    color: #1d2127;
    box-shadow:
      0 1px 2px rgb(0 0 0 / 0.08),
      0 12px 32px rgb(0 0 0 / 0.18);
    overflow: hidden;
    animation: doc var(--loop) ease-out infinite;
  }
  .doc-head {
    display: flex;
    flex-direction: column;
    gap: 2px;
    padding-bottom: 10px;
    margin-bottom: 10px;
    border-bottom: 1px solid #e3e6eb;
  }
  .doc-title {
    font-weight: 700;
    font-size: 13px;
  }
  .doc-sub {
    font-size: 11px;
    color: #6b7280;
  }
  .rows {
    display: flex;
    flex-direction: column;
    gap: 9px;
    font-size: 11px;
  }
  .row {
    display: flex;
    justify-content: space-between;
    gap: 8px;
  }
  .num {
    font-family: var(--font-mono);
    font-size: 10.5px;
  }
  .masked {
    position: relative;
  }
  .bar {
    position: absolute;
    inset: -2px -3px;
    background: #000000;
    border-radius: 2px;
    transform-origin: left center;
    transform: scaleX(0);
    animation: bar var(--loop) cubic-bezier(0.6, 0, 0.3, 1) infinite;
  }
  .bar.late {
    animation-name: bar-late;
  }
  .line {
    height: 7px;
    border-radius: 4px;
    background: #eceef2;
  }
  .w90 {
    width: 90%;
  }
  .w70 {
    width: 70%;
  }
  .w80 {
    width: 80%;
  }
  .stamp {
    position: absolute;
    inset: -40%;
    display: flex;
    flex-direction: column;
    justify-content: space-around;
    transform: rotate(-30deg);
    color: #1e1e1e;
    font-size: 10px;
    font-weight: 600;
    white-space: nowrap;
    opacity: 0;
    pointer-events: none;
    animation: stamp var(--loop) ease-out infinite;
  }
  .stamp span:nth-child(even) {
    padding-left: 80px;
  }

  .chip {
    position: absolute;
    display: inline-flex;
    align-items: center;
    gap: 6px;
    padding: 7px 12px;
    border-radius: 999px;
    font-size: 12px;
    font-weight: 600;
    background: var(--surface);
    color: var(--fg);
    border: 1px solid var(--border);
    box-shadow: 0 6px 18px rgb(0 0 0 / 0.14);
    white-space: nowrap;
    opacity: 0;
  }
  .link {
    left: 50%;
    bottom: 22px;
    transform: translateX(-50%);
    animation: link var(--loop) ease-out infinite;
  }
  .url {
    font-family: var(--font-mono);
    font-size: 11px;
    animation: url var(--loop) linear infinite;
  }
  .copied {
    padding: 1px 8px;
    border-radius: 999px;
    background: var(--ok-subtle);
    color: var(--ok);
    font-size: 11px;
    animation: copied var(--loop) linear infinite;
  }
  .opened {
    right: 14px;
    top: 16px;
    background: var(--primary-subtle);
    color: var(--primary);
    border-color: transparent;
    animation: opened var(--loop) ease-out infinite;
  }
  .revoked {
    left: 14px;
    top: 16px;
    background: var(--bad-subtle);
    color: var(--bad);
    border-color: transparent;
    animation: revoked var(--loop) ease-out infinite;
  }

  .timeline {
    list-style: none;
    margin: 0;
    padding: 0;
    display: grid;
    grid-template-columns: repeat(4, 1fr);
    gap: var(--space-2);
  }
  .timeline li {
    display: flex;
    align-items: center;
    gap: 6px;
    font-size: 12px;
    font-weight: 600;
    color: var(--fg-muted);
    padding: 6px 8px;
    border-radius: var(--radius-md);
    animation: var(--loop) linear infinite;
  }
  .dot {
    display: grid;
    place-items: center;
    width: 18px;
    height: 18px;
    border-radius: 50%;
    background: var(--sunken);
    font-size: 11px;
    flex-shrink: 0;
  }
  .timeline .s1 {
    animation-name: step1;
  }
  .timeline .s2 {
    animation-name: step2;
  }
  .timeline .s3 {
    animation-name: step3;
  }
  .timeline .s4 {
    animation-name: step4;
  }

  @keyframes doc {
    0% { opacity: 0; transform: translateY(14px); }
    5%, 94% { opacity: 1; transform: none; }
    100% { opacity: 0; transform: translateY(-6px); }
  }
  @keyframes bar {
    0%, 12% { transform: scaleX(0); }
    20%, 96% { transform: scaleX(1); }
    100% { transform: scaleX(0); }
  }
  @keyframes bar-late {
    0%, 19% { transform: scaleX(0); }
    27%, 96% { transform: scaleX(1); }
    100% { transform: scaleX(0); }
  }
  @keyframes stamp {
    0%, 30% { opacity: 0; transform: rotate(-30deg) scale(1.08); }
    38%, 94% { opacity: 0.16; transform: rotate(-30deg) scale(1); }
    100% { opacity: 0; transform: rotate(-30deg); }
  }
  @keyframes link {
    0%, 44% { opacity: 0; transform: translate(-50%, 16px); }
    50%, 94% { opacity: 1; transform: translate(-50%, 0); }
    100% { opacity: 0; transform: translate(-50%, 0); }
  }
  @keyframes url {
    0%, 76% { text-decoration: none; opacity: 1; }
    80%, 100% { text-decoration: line-through; opacity: 0.55; }
  }
  @keyframes copied {
    0%, 50% { opacity: 0; }
    53%, 62% { opacity: 1; }
    66%, 100% { opacity: 0; }
  }
  @keyframes opened {
    0%, 62% { opacity: 0; transform: scale(0.6); }
    66% { opacity: 1; transform: scale(1.08); }
    69%, 94% { opacity: 1; transform: scale(1); }
    100% { opacity: 0; }
  }
  @keyframes revoked {
    0%, 76% { opacity: 0; transform: translateY(-8px); }
    80%, 94% { opacity: 1; transform: none; }
    100% { opacity: 0; }
  }
  @keyframes step1 {
    0%, 11%, 30%, 100% { background: transparent; color: var(--fg-muted); }
    13%, 28% { background: var(--primary-subtle); color: var(--primary); }
  }
  @keyframes step2 {
    0%, 30%, 45%, 100% { background: transparent; color: var(--fg-muted); }
    32%, 43% { background: var(--primary-subtle); color: var(--primary); }
  }
  @keyframes step3 {
    0%, 45%, 75%, 100% { background: transparent; color: var(--fg-muted); }
    47%, 73% { background: var(--primary-subtle); color: var(--primary); }
  }
  @keyframes step4 {
    0%, 75%, 96%, 100% { background: transparent; color: var(--fg-muted); }
    77%, 94% { background: var(--bad-subtle); color: var(--bad); }
  }

  @media (max-width: 520px) {
    .timeline {
      grid-template-columns: repeat(2, 1fr);
    }
  }

  /* Reduced motion: the finished application, before it is revoked. */
  @media (prefers-reduced-motion: reduce) {
    .demo * {
      animation: none !important;
    }
    .doc {
      opacity: 1;
    }
    .bar {
      transform: scaleX(1);
    }
    .stamp {
      opacity: 0.16;
    }
    .link,
    .opened {
      opacity: 1;
    }
    .copied {
      display: none;
    }
  }
</style>
