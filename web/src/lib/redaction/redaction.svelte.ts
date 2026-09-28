import { t } from '../i18n.svelte';
import { CanvasError, decodeImage, jpegCheck, release, renderRedacted, verifyRedacted } from './export';
import {
  contains,
  corners,
  isLargeEnough,
  opposite,
  rectFromPoints,
  translate,
  type Corner,
  type NRect,
  type Point,
} from './geometry';
import { maxPdfPages, openPdf, PdfPasswordError, PdfTooLongError, type PdfDocument } from './pdf';
import { buildPdf, type ImagePage } from './pdf-writer';
import type { RedactionPreset } from './presets';
import { findMatches, type TextRun } from './text-search';

type Gesture =
  | { kind: 'draw'; from: Point }
  | { kind: 'move'; index: number; from: Point; origin: NRect; moved: boolean }
  | { kind: 'resize'; index: number; anchor: Point; moved: boolean };

// One editing session over an image (one page) or a PDF (many). Boxes are kept
// per page; only the page on screen is rendered, so a long PDF stays bounded
// in memory.
class Redaction {
  kind = $state<'image' | 'pdf' | null>(null);
  current = $state.raw<HTMLCanvasElement | null>(null);
  pageCount = $state(0);
  page = $state(0);
  boxesByPage = $state<NRect[][]>([]);
  draft = $state<NRect | null>(null);
  selected = $state<number | null>(null);
  zoom = $state(1);
  panning = $state(false);
  loading = $state(false);
  exporting = $state(false);
  error = $state<string | null>(null);
  canUndo = $state(false);

  search = $state('');
  searching = $state(false);
  matches = $state<{ page: number; rect: NRect }[]>([]);
  pageHasText = $state(true);

  boxes = $derived(this.boxesByPage[this.page] ?? []);
  totalBoxes = $derived(this.boxesByPage.reduce((n, b) => n + b.length, 0));

  #pdf: PdfDocument | null = null;
  #text = new Map<number, TextRun[]>();
  #history: NRect[][][] = [];
  #gesture: Gesture | null = null;

  static canRedact(type: string): boolean {
    return type.startsWith('image/') || type === 'application/pdf';
  }

  async load(file: Blob): Promise<boolean> {
    this.reset();
    this.loading = true;
    try {
      if (file.type === 'application/pdf') {
        this.#pdf = await openPdf(file);
        this.kind = 'pdf';
        this.pageCount = this.#pdf.pageCount;
        this.boxesByPage = Array.from({ length: this.pageCount }, () => []);
        await this.#showPage(0);
      } else {
        this.current = await decodeImage(file);
        this.kind = 'image';
        this.pageCount = 1;
        this.boxesByPage = [[]];
        this.pageHasText = false;
      }
      return true;
    } catch (e) {
      this.error =
        e instanceof PdfPasswordError
          ? t('redact.err.pdfPassword')
          : e instanceof PdfTooLongError
            ? t('redact.err.pdfPages', { n: maxPdfPages })
            : e instanceof CanvasError
              ? t('redact.err.canvas')
              : t(file.type === 'application/pdf' ? 'redact.err.pdf' : 'redact.err.image');
      this.reset(false);
      return false;
    } finally {
      this.loading = false;
    }
  }

  async goTo(index: number) {
    if (index < 0 || index >= this.pageCount || index === this.page || this.kind !== 'pdf') return;
    this.selected = null;
    this.draft = null;
    await this.#showPage(index);
  }

  pointerDown(p: Point, handle: Corner | null) {
    const sel = this.selected;
    if (sel !== null && handle) {
      this.#gesture = { kind: 'resize', index: sel, anchor: corners(this.boxes[sel])[opposite[handle]], moved: false };
      return;
    }
    const hit = this.#hit(p);
    if (hit !== null) {
      this.selected = hit;
      this.#gesture = { kind: 'move', index: hit, from: p, origin: { ...this.boxes[hit] }, moved: false };
      return;
    }
    this.selected = null;
    this.#gesture = { kind: 'draw', from: p };
    this.draft = rectFromPoints(p, p);
  }

  pointerMove(p: Point) {
    const g = this.#gesture;
    if (!g) return;
    if (g.kind === 'draw') {
      this.draft = rectFromPoints(g.from, p);
      return;
    }
    if (!g.moved) {
      this.#snapshot();
      g.moved = true;
    }
    const page = this.boxesByPage[this.page];
    page[g.index] = g.kind === 'move' ? translate(g.origin, p.x - g.from.x, p.y - g.from.y) : rectFromPoints(g.anchor, p);
  }

  pointerUp() {
    const g = this.#gesture;
    this.#gesture = null;
    if (g?.kind === 'draw') {
      const d = this.draft;
      this.draft = null;
      if (d && isLargeEnough(d)) {
        this.#snapshot();
        this.boxesByPage[this.page].push(d);
        this.selected = this.boxes.length - 1;
      }
    } else if (g?.kind === 'resize' && !isLargeEnough(this.boxes[g.index])) {
      this.undo();
    }
  }

  removeSelected() {
    if (this.selected === null) return;
    this.#snapshot();
    this.boxesByPage[this.page].splice(this.selected, 1);
    this.selected = null;
  }

  undo() {
    const prev = this.#history.pop();
    if (!prev) return;
    this.boxesByPage = prev;
    this.selected = null;
    this.canUndo = this.#history.length > 0;
  }

  applyPreset(p: RedactionPreset) {
    this.#snapshot();
    this.boxesByPage[this.page].push(...p.boxes.map((b) => ({ ...b })));
    this.selected = null;
  }

  setZoom(z: number) {
    this.zoom = Math.min(4, Math.max(1, z));
  }

  // Finds `search` on every page of a PDF; the boxes are only added by
  // `blackOutMatches`, so the reader sees what will be covered first.
  async find() {
    const term = this.search.trim();
    if (!this.#pdf || !term) {
      this.matches = [];
      return;
    }
    this.searching = true;
    const found: { page: number; rect: NRect }[] = [];
    for (let i = 0; i < this.pageCount; i++) {
      for (const rect of findMatches(await this.#runs(i), term)) found.push({ page: i, rect });
    }
    if (term === this.search.trim()) this.matches = found;
    this.searching = false;
  }

  blackOutMatches() {
    if (!this.matches.length) return;
    this.#snapshot();
    for (const m of this.matches) this.boxesByPage[m.page].push({ ...m.rect });
    this.matches = [];
    this.search = '';
    this.selected = null;
  }

  // Resolves to the redacted file, or null having set `error`. Nothing is
  // returned unless the exported file was decoded and every box checked.
  async export(): Promise<Blob | null> {
    if (!this.current) return null;
    this.exporting = true;
    this.error = null;
    try {
      const out = this.kind === 'pdf' ? await this.#exportPdf() : await this.#exportImage();
      if (!out) this.error = t('redact.err.verify');
      return out;
    } catch (e) {
      this.error = t(e instanceof CanvasError ? 'redact.err.canvas' : 'redact.err.encode');
      return null;
    } finally {
      this.exporting = false;
    }
  }

  reset(clearError = true) {
    release(this.current);
    this.#pdf?.destroy();
    this.#pdf = null;
    this.#text.clear();
    this.kind = null;
    this.current = null;
    this.pageCount = 0;
    this.page = 0;
    this.boxesByPage = [];
    this.draft = null;
    this.selected = null;
    this.zoom = 1;
    this.panning = false;
    this.search = '';
    this.matches = [];
    this.pageHasText = true;
    if (clearError) this.error = null;
    this.#history = [];
    this.#gesture = null;
    this.canUndo = false;
  }

  async #exportImage(): Promise<Blob | null> {
    const src = this.current!;
    const boxes = $state.snapshot(this.boxes);
    const png = await renderRedacted(src, boxes);
    return (await verifyRedacted(png, src.width, src.height, boxes)) ? png : null;
  }

  async #exportPdf(): Promise<Blob | null> {
    const pdf = this.#pdf!;
    const all = $state.snapshot(this.boxesByPage);
    const pages: ImagePage[] = [];
    for (let i = 0; i < this.pageCount; i++) {
      const canvas = i === this.page ? this.current! : await pdf.render(i);
      try {
        const jpeg = await renderRedacted(canvas, all[i], 'image/jpeg');
        if (!(await verifyRedacted(jpeg, canvas.width, canvas.height, all[i], jpegCheck))) return null;
        const size = pdf.pageSize(i);
        pages.push({
          jpeg: new Uint8Array(await jpeg.arrayBuffer()),
          pixelWidth: canvas.width,
          pixelHeight: canvas.height,
          width: size.width,
          height: size.height,
        });
      } finally {
        if (canvas !== this.current) release(canvas);
      }
    }
    return new Blob([buildPdf(pages) as BlobPart], { type: 'application/pdf' });
  }

  async #showPage(index: number) {
    const pdf = this.#pdf!;
    this.loading = true;
    try {
      const canvas = await pdf.render(index);
      release(this.current);
      this.current = canvas;
      this.page = index;
      this.pageHasText = (await this.#runs(index)).length > 0;
    } finally {
      this.loading = false;
    }
  }

  async #runs(index: number): Promise<TextRun[]> {
    let runs = this.#text.get(index);
    if (!runs) {
      runs = await this.#pdf!.text(index);
      this.#text.set(index, runs);
    }
    return runs;
  }

  #hit(p: Point): number | null {
    for (let i = this.boxes.length - 1; i >= 0; i--) {
      if (contains(this.boxes[i], p)) return i;
    }
    return null;
  }

  #snapshot() {
    this.#history.push($state.snapshot(this.boxesByPage));
    this.canUndo = true;
  }
}

export const redaction = new Redaction();
export const canRedact = (type: string) => Redaction.canRedact(type);
