import type { TextRun } from './text-search';

export const maxPdfPages = 50;
// Roughly 200 dpi: small print stays legible, and a page stays a few MB.
const exportScale = 200 / 72;
const maxEdge = 3000;

export interface PdfDocument {
  pageCount: number;
  // Size in PDF points, as the page is displayed (rotation applied).
  pageSize(index: number): { width: number; height: number };
  render(index: number): Promise<HTMLCanvasElement>;
  text(index: number): Promise<TextRun[]>;
  destroy(): void;
}

export class PdfPasswordError extends Error {}
export class PdfTooLongError extends Error {}

// pdf.js is large, so it is only fetched the first time someone redacts a PDF.
async function loadPdfJs() {
  const [pdfjs, worker] = await Promise.all([
    import('pdfjs-dist'),
    import('pdfjs-dist/build/pdf.worker.min.mjs?url'),
  ]);
  pdfjs.GlobalWorkerOptions.workerSrc = worker.default;
  return pdfjs;
}

export async function openPdf(file: Blob): Promise<PdfDocument> {
  const pdfjs = await loadPdfJs();
  const task = pdfjs.getDocument({
    data: new Uint8Array(await file.arrayBuffer()),
    // No WebAssembly and no scripting: the page's CSP allows neither, and
    // a document being redacted has no business running code.
    useWasm: false,
    enableXfa: false,
  });
  let doc;
  try {
    doc = await task.promise;
  } catch (e) {
    void task.destroy();
    if (e instanceof pdfjs.PasswordException) throw new PdfPasswordError();
    throw e;
  }
  if (doc.numPages > maxPdfPages) {
    void task.destroy();
    throw new PdfTooLongError();
  }

  const sizes: { width: number; height: number }[] = [];
  for (let i = 1; i <= doc.numPages; i++) {
    const vp = (await doc.getPage(i)).getViewport({ scale: 1 });
    sizes.push({ width: vp.width, height: vp.height });
  }

  const d = doc;
  return {
    pageCount: d.numPages,
    pageSize: (i) => sizes[i],
    async render(i) {
      const page = await d.getPage(i + 1);
      const base = page.getViewport({ scale: 1 });
      const scale = Math.min(exportScale, maxEdge / Math.max(base.width, base.height));
      const viewport = page.getViewport({ scale });
      const canvas = document.createElement('canvas');
      canvas.width = Math.round(viewport.width);
      canvas.height = Math.round(viewport.height);
      await page.render({ canvas, viewport, background: '#ffffff' }).promise;
      return canvas;
    },
    async text(i) {
      const page = await d.getPage(i + 1);
      const viewport = page.getViewport({ scale: 1 });
      const content = await page.getTextContent();
      const runs: TextRun[] = [];
      for (const item of content.items) {
        if (!('str' in item) || !item.str.trim()) continue;
        const m = pdfjs.Util.transform(viewport.transform, item.transform) as number[];
        const h = Math.hypot(m[2], m[3]);
        runs.push({
          str: item.str,
          x: m[4] / viewport.width,
          y: (m[5] - h) / viewport.height,
          w: item.width / viewport.width,
          h: (h * 1.15) / viewport.height,
        });
      }
      return runs;
    },
    destroy: () => void task.destroy(),
  };
}
