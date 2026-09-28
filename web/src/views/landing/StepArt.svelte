<script lang="ts">
  import Icon from '../../components/Icon.svelte';
  import { t } from '../../lib/i18n.svelte';
  import { inview } from '../../lib/inview';

  let { kind }: { kind: 'store' | 'redact' | 'stamp' | 'revoke' } = $props();
</script>

<div class="art {kind}" use:inview aria-hidden="true">
  {#if kind === 'store'}
    <div class="sheet s1"><span class="tag">SCHUFA</span></div>
    <div class="sheet s2"><span class="tag">{t('demo.payslip')}</span></div>
    <div class="sheet s3"><span class="tag">{t('demo.id')}</span></div>
  {:else if kind === 'redact'}
    <div class="sheet solo">
      <div class="l"></div>
      <div class="l short"></div>
      <div class="l mono">CAN 123456<span class="bar"></span></div>
      <div class="l"></div>
    </div>
  {:else if kind === 'stamp'}
    <div class="sheet solo">
      <div class="l"></div>
      <div class="l short"></div>
      <div class="l"></div>
      <div class="diag"><span>Musterstr. 5 · #a3f9c1</span><span>Musterstr. 5 · #a3f9c1</span></div>
    </div>
    <div class="pill"><Icon name="link" size={12} /> Musterstr. 5</div>
  {:else}
    <div class="pill seen"><Icon name="eye" size={12} /> {t('demo.opened')}</div>
    <div class="toggle"><span class="knob"></span></div>
    <div class="pill gone"><Icon name="revoke" size={12} /> {t('demo.revoked')}</div>
  {/if}
</div>

<style>
  .art {
    --t: 4s;
    position: relative;
    height: 132px;
    border-radius: var(--radius-md);
    background: var(--sunken);
    overflow: hidden;
  }
  .sheet {
    position: absolute;
    width: 78px;
    height: 100px;
    border-radius: 6px;
    background: #ffffff;
    box-shadow: 0 4px 14px rgb(0 0 0 / 0.16);
    display: flex;
    flex-direction: column;
    justify-content: flex-end;
    padding: 8px;
  }
  .tag {
    font-size: 9px;
    font-weight: 700;
    color: #35618e;
  }

  /* 1 · three documents settle into a stack */
  .store .sheet {
    left: 50%;
    top: 16px;
    opacity: 0;
  }
  .store .s1 {
    margin-left: -64px;
    rotate: -8deg;
  }
  .store .s2 {
    margin-left: -39px;
  }
  .store .s3 {
    margin-left: -14px;
    rotate: 8deg;
  }
  .store:global([data-inview]) .sheet {
    animation: drop var(--t) ease-out infinite;
  }
  .store:global([data-inview]) .s2 {
    animation-delay: 0.25s;
  }
  .store:global([data-inview]) .s3 {
    animation-delay: 0.5s;
  }

  /* 2 and 3 · a single page */
  .solo {
    left: 50%;
    top: 16px;
    margin-left: -52px;
    width: 104px;
    justify-content: flex-start;
    gap: 9px;
    padding: 14px 10px;
    overflow: hidden;
  }
  .l {
    position: relative;
    height: 6px;
    border-radius: 3px;
    background: #e5e8ee;
  }
  .l.short {
    width: 60%;
  }
  .l.mono {
    height: auto;
    background: none;
    font-family: var(--font-mono);
    font-size: 9px;
    color: #1d2127;
  }
  .bar {
    position: absolute;
    inset: -1px -2px;
    background: #000000;
    border-radius: 2px;
    transform-origin: left;
    transform: scaleX(0);
  }
  .redact:global([data-inview]) .bar {
    animation: sweep 3.2s cubic-bezier(0.6, 0, 0.3, 1) infinite;
  }

  .diag {
    position: absolute;
    inset: -30%;
    display: flex;
    flex-direction: column;
    justify-content: space-around;
    transform: rotate(-30deg);
    font-size: 8px;
    font-weight: 700;
    color: #1e1e1e;
    white-space: nowrap;
    opacity: 0;
  }
  .stamp:global([data-inview]) .diag {
    animation: stamp-in var(--t) ease-out infinite;
  }

  .pill {
    position: absolute;
    display: inline-flex;
    align-items: center;
    gap: 5px;
    padding: 4px 10px;
    border-radius: 999px;
    font-size: 11px;
    font-weight: 600;
    background: var(--surface);
    border: 1px solid var(--border);
    white-space: nowrap;
  }
  .stamp .pill {
    right: 12px;
    bottom: 12px;
    opacity: 0;
  }
  .stamp:global([data-inview]) .pill {
    animation: rise var(--t) ease-out infinite;
  }

  /* 4 · opened, then switched off */
  .seen {
    left: 50%;
    top: 16px;
    transform: translateX(-50%);
    background: var(--primary-subtle);
    color: var(--primary);
    border-color: transparent;
    opacity: 0;
  }
  .gone {
    left: 50%;
    bottom: 14px;
    transform: translateX(-50%);
    background: var(--bad-subtle);
    color: var(--bad);
    border-color: transparent;
    opacity: 0;
  }
  .toggle {
    position: absolute;
    left: 50%;
    top: 52px;
    width: 46px;
    height: 26px;
    margin-left: -23px;
    border-radius: 999px;
    background: var(--ok);
  }
  .knob {
    position: absolute;
    top: 3px;
    left: 23px;
    width: 20px;
    height: 20px;
    border-radius: 50%;
    background: #ffffff;
  }
  .revoke:global([data-inview]) .seen {
    animation: pop var(--t) ease-out infinite;
  }
  .revoke:global([data-inview]) .toggle {
    animation: switch-bg var(--t) ease-in-out infinite;
  }
  .revoke:global([data-inview]) .knob {
    animation: switch-knob var(--t) ease-in-out infinite;
  }
  .revoke:global([data-inview]) .gone {
    animation: gone var(--t) ease-out infinite;
  }

  @keyframes drop {
    0% { opacity: 0; translate: 0 -24px; }
    12%, 88% { opacity: 1; translate: 0 0; }
    100% { opacity: 0; translate: 0 0; }
  }
  @keyframes sweep {
    0%, 15% { transform: scaleX(0); }
    40%, 88% { transform: scaleX(1); }
    100% { transform: scaleX(0); }
  }
  @keyframes stamp-in {
    0%, 12% { opacity: 0; }
    30%, 88% { opacity: 0.35; }
    100% { opacity: 0; }
  }
  @keyframes rise {
    0%, 35% { opacity: 0; translate: 0 8px; }
    45%, 88% { opacity: 1; translate: 0 0; }
    100% { opacity: 0; }
  }
  @keyframes pop {
    0%, 8% { opacity: 0; scale: 0.7; }
    16% { opacity: 1; scale: 1.08; }
    20%, 88% { opacity: 1; scale: 1; }
    100% { opacity: 0; }
  }
  @keyframes switch-bg {
    0%, 45% { background: var(--ok); }
    55%, 92% { background: var(--border-strong); }
    100% { background: var(--ok); }
  }
  @keyframes switch-knob {
    0%, 45% { left: 23px; }
    55%, 92% { left: 3px; }
    100% { left: 23px; }
  }
  @keyframes gone {
    0%, 55% { opacity: 0; translate: 0 6px; }
    62%, 90% { opacity: 1; translate: 0 0; }
    100% { opacity: 0; }
  }

  @media (prefers-reduced-motion: reduce) {
    .art * {
      animation: none !important;
    }
    .store .sheet,
    .stamp .pill,
    .seen,
    .gone {
      opacity: 1;
    }
    .bar {
      transform: scaleX(1);
    }
    .diag {
      opacity: 0.35;
    }
    .toggle {
      background: var(--border-strong);
    }
    .knob {
      left: 3px;
    }
  }
</style>
