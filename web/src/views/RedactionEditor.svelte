<script lang="ts">
  import Alert from '../components/Alert.svelte';
  import Button from '../components/Button.svelte';
  import Spinner from '../components/Spinner.svelte';
  import { t } from '../lib/i18n.svelte';
  import { corners, type Corner, type Point } from '../lib/redaction/geometry';
  import { presets } from '../lib/redaction/presets';
  import { redaction } from '../lib/redaction/redaction.svelte';

  let { oncancel, ondone }: { oncancel: () => void; ondone: (out: Blob) => void } = $props();

  let canvas: HTMLCanvasElement | undefined = $state();
  let availW = $state(0);
  let availH = $state(0);

  const size = $derived.by(() => {
    const src = redaction.current;
    // The viewport's padding is inside clientWidth/Height.
    const cw = availW - 32;
    const ch = availH - 32;
    if (!src || cw <= 0 || ch <= 0) return { w: 0, h: 0 };
    const aspect = src.width / src.height;
    const fitW = Math.min(cw, ch * aspect);
    const w = Math.floor(fitW * redaction.zoom);
    return { w, h: Math.floor(w / aspect) };
  });

  const pageMatches = $derived(redaction.matches.filter((m) => m.page === redaction.page));

  $effect(() => {
    const src = redaction.current;
    const c = canvas;
    if (!src || !c || !size.w) return;
    const dpr = window.devicePixelRatio || 1;
    c.width = Math.round(size.w * dpr);
    c.height = Math.round(size.h * dpr);
    const ctx = c.getContext('2d');
    if (!ctx) return;
    const W = c.width;
    const H = c.height;
    const style = getComputedStyle(c);
    const primary = style.getPropertyValue('--primary').trim() || '#35618e';
    const warn = style.getPropertyValue('--warn').trim() || '#7a5900';

    ctx.imageSmoothingQuality = 'high';
    ctx.drawImage(src, 0, 0, W, H);

    ctx.fillStyle = '#000000';
    for (const b of redaction.boxes) ctx.fillRect(b.x * W, b.y * H, b.w * W, b.h * H);

    // Search hits are shown, not applied, until the reader confirms them.
    ctx.lineWidth = 2 * dpr;
    ctx.strokeStyle = warn;
    ctx.setLineDash([4 * dpr, 3 * dpr]);
    for (const m of pageMatches) ctx.strokeRect(m.rect.x * W, m.rect.y * H, m.rect.w * W, m.rect.h * H);

    const d = redaction.draft;
    if (d) {
      ctx.fillRect(d.x * W, d.y * H, d.w * W, d.h * H);
      ctx.setLineDash([6 * dpr, 4 * dpr]);
      ctx.strokeStyle = primary;
      ctx.strokeRect(d.x * W, d.y * H, d.w * W, d.h * H);
    }
    ctx.setLineDash([]);

    const sel = redaction.selected;
    if (sel !== null && redaction.boxes[sel]) {
      const b = redaction.boxes[sel];
      ctx.strokeStyle = primary;
      ctx.strokeRect(b.x * W, b.y * H, b.w * W, b.h * H);
      const r = 6 * dpr;
      ctx.fillStyle = primary;
      for (const p of Object.values(corners(b))) ctx.fillRect(p.x * W - r, p.y * H - r, 2 * r, 2 * r);
    }
  });

  let searchTimer: ReturnType<typeof setTimeout> | undefined;
  function onSearch() {
    clearTimeout(searchTimer);
    searchTimer = setTimeout(() => redaction.find(), 200);
  }

  function norm(e: PointerEvent): Point {
    const rect = canvas!.getBoundingClientRect();
    return { x: (e.clientX - rect.left) / rect.width, y: (e.clientY - rect.top) / rect.height };
  }

  function handleAt(e: PointerEvent): Corner | null {
    const sel = redaction.selected;
    if (sel === null || !canvas) return null;
    const rect = canvas.getBoundingClientRect();
    const reach = e.pointerType === 'touch' ? 24 : 12;
    for (const [name, p] of Object.entries(corners(redaction.boxes[sel])) as [Corner, Point][]) {
      const dx = rect.left + p.x * rect.width - e.clientX;
      const dy = rect.top + p.y * rect.height - e.clientY;
      if (Math.hypot(dx, dy) <= reach) return name;
    }
    return null;
  }

  function down(e: PointerEvent) {
    if (redaction.panning || e.button !== 0) return;
    canvas!.setPointerCapture(e.pointerId);
    redaction.pointerDown(norm(e), handleAt(e));
  }

  function move(e: PointerEvent) {
    if (!redaction.panning && canvas!.hasPointerCapture(e.pointerId)) redaction.pointerMove(norm(e));
  }

  function up(e: PointerEvent) {
    if (canvas!.hasPointerCapture(e.pointerId)) {
      canvas!.releasePointerCapture(e.pointerId);
      redaction.pointerUp();
    }
  }

  function keydown(e: KeyboardEvent) {
    if (e.target instanceof HTMLInputElement || e.target instanceof HTMLTextAreaElement) return;
    if ((e.key === 'Delete' || e.key === 'Backspace') && redaction.selected !== null) {
      e.preventDefault();
      redaction.removeSelected();
    } else if (e.key === 'z' && (e.ctrlKey || e.metaKey)) {
      e.preventDefault();
      redaction.undo();
    } else if (e.key === 'PageDown') {
      void redaction.goTo(redaction.page + 1);
    } else if (e.key === 'PageUp') {
      void redaction.goTo(redaction.page - 1);
    }
  }

  async function done() {
    const out = await redaction.export();
    if (out) ondone(out);
  }
</script>

<svelte:window onkeydown={keydown} />

<div class="editor">
  <div class="toolbar">
    <div class="row">
      <Button icon="undo" tooltip={t('redact.undo')} disabled={!redaction.canUndo} onclick={() => redaction.undo()} />
      <Button
        icon="trash"
        variant="destructive"
        tooltip={t('redact.remove')}
        disabled={redaction.selected === null}
        onclick={() => redaction.removeSelected()}
      />
      <span class="sep"></span>
      <Button
        icon="zoomOut"
        tooltip={t('redact.zoomOut')}
        disabled={redaction.zoom <= 1}
        onclick={() => redaction.setZoom(redaction.zoom - 0.5)}
      />
      <Button
        icon="zoomIn"
        tooltip={t('redact.zoomIn')}
        disabled={redaction.zoom >= 4}
        onclick={() => redaction.setZoom(redaction.zoom + 0.5)}
      />
      <Button
        icon={redaction.panning ? 'hand' : 'pen'}
        tooltip={redaction.panning ? t('redact.panning') : t('redact.drawing')}
        onclick={() => (redaction.panning = !redaction.panning)}
      />
      {#if redaction.pageCount > 1}
        <span class="sep"></span>
        <Button
          icon="chevronLeft"
          tooltip={t('redact.prevPage')}
          disabled={redaction.page === 0 || redaction.loading}
          onclick={() => redaction.goTo(redaction.page - 1)}
        />
        <span class="small pages">{t('redact.page', { n: redaction.page + 1, total: redaction.pageCount })}</span>
        <Button
          icon="chevronRight"
          tooltip={t('redact.nextPage')}
          disabled={redaction.page >= redaction.pageCount - 1 || redaction.loading}
          onclick={() => redaction.goTo(redaction.page + 1)}
        />
      {/if}
      {#if presets.length}
        <span class="sep"></span>
        {#each presets as p (p.name)}
          <Button small onclick={() => redaction.applyPreset(p)}>{p.name}</Button>
        {/each}
      {/if}
    </div>

    {#if redaction.kind === 'pdf'}
      <form
        class="search"
        role="search"
        onsubmit={(e) => {
          e.preventDefault();
          redaction.blackOutMatches();
        }}
      >
        <input
          type="search"
          aria-label={t('redact.find')}
          placeholder={t('redact.findPlaceholder')}
          bind:value={redaction.search}
          oninput={onSearch}
        />
        {#if redaction.searching}
          <Spinner />
        {:else if redaction.search.trim() && !redaction.matches.length}
          <span class="small muted">{t('redact.noMatches')}</span>
        {/if}
        <Button type="submit" small icon="redact" disabled={!redaction.matches.length}
          >{t('redact.blackOut', { n: redaction.matches.length })}</Button
        >
      </form>
      {#if !redaction.pageHasText && !redaction.loading}
        <p class="small muted">{t('redact.noText')}</p>
      {/if}
    {:else}
      <p class="small muted">{t('redact.imageNoText')}</p>
    {/if}
    <p class="small muted hint">{t('redact.hint')}</p>
  </div>

  <div class="viewport" bind:clientWidth={availW} bind:clientHeight={availH}>
    {#if redaction.current}
      <div class="stage" style:width="{size.w}px" style:height="{size.h}px">
        <canvas
          bind:this={canvas}
          style:width="{size.w}px"
          style:height="{size.h}px"
          class:panning={redaction.panning}
          aria-label={t('redact.canvas')}
          onpointerdown={down}
          onpointermove={move}
          onpointerup={up}
          onpointercancel={up}
        ></canvas>
        {#if redaction.loading}<div class="busy"><Spinner large /></div>{/if}
      </div>
    {:else if redaction.loading}
      <div class="center"><Spinner large /></div>
    {/if}
  </div>

  <div class="footer">
    {#if redaction.error}
      <Alert tone="bad">{redaction.error}</Alert>
    {/if}
    <div class="spread">
      <span class="small muted">
        {t('redact.boxes', { n: redaction.totalBoxes })} · {redaction.kind === 'pdf'
          ? t('redact.outputPdf')
          : t('redact.outputImage')}
      </span>
      <div class="row">
        <Button onclick={oncancel}>{t('common.cancel')}</Button>
        <Button
          variant="primary"
          icon="check"
          busy={redaction.exporting}
          disabled={!redaction.current || redaction.loading}
          onclick={done}>{t('redact.use')}</Button
        >
      </div>
    </div>
  </div>
</div>

<style>
  .editor {
    display: flex;
    flex-direction: column;
    flex: 1;
    min-height: 0;
  }
  .toolbar {
    padding: var(--space-3) var(--space-4);
    border-bottom: 1px solid var(--border);
    display: flex;
    flex-direction: column;
    gap: var(--space-2);
  }
  .sep {
    width: 1px;
    height: 24px;
    background: var(--border);
    margin: 0 var(--space-1);
  }
  .pages {
    min-width: 7em;
    text-align: center;
    font-variant-numeric: tabular-nums;
  }
  .search {
    display: flex;
    align-items: center;
    gap: var(--space-2);
    flex-wrap: wrap;
  }
  .search input {
    flex: 1;
    min-width: 180px;
    min-height: 32px;
    padding: 0 var(--space-3);
    border: 1px solid var(--border);
    border-radius: var(--radius-md);
    background: var(--surface);
  }
  .search input:focus {
    border-color: var(--primary);
    outline: 1px solid var(--primary);
  }
  .viewport {
    flex: 1;
    min-height: 0;
    overflow: auto;
    background: var(--sunken);
    padding: var(--space-4);
    display: grid;
  }
  .stage {
    margin: auto;
    position: relative;
  }
  .busy {
    position: absolute;
    inset: 0;
    display: grid;
    place-items: center;
    background: color-mix(in srgb, var(--surface) 55%, transparent);
  }
  .center {
    display: grid;
    place-items: center;
  }
  canvas {
    display: block;
    touch-action: none;
    cursor: crosshair;
    box-shadow: 0 0 0 1px var(--border);
  }
  canvas.panning {
    touch-action: auto;
    cursor: grab;
  }
  .footer {
    padding: var(--space-3) var(--space-4);
    border-top: 1px solid var(--border);
    display: flex;
    flex-direction: column;
    gap: var(--space-2);
  }
</style>
