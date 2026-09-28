import { boxesAreBlack, toPixelRect, type NRect } from './geometry';

export const maxEdge = 4096;

// A pixel value inside the exported file, not a UI colour: solid, opaque
// black. Blur and pixelation can be reversed or read by a model.
const redactionFill = '#000000';

export const jpegCheck = { tolerance: 24, inset: 3 };

export class CanvasError extends Error {}

function canvas(width: number, height: number): HTMLCanvasElement {
  const c = document.createElement('canvas');
  c.width = width;
  c.height = height;
  return c;
}

function context(c: HTMLCanvasElement): CanvasRenderingContext2D {
  const ctx = c.getContext('2d', { willReadFrequently: true });
  if (!ctx) throw new CanvasError();
  return ctx;
}

export function release(c: HTMLCanvasElement | null | undefined) {
  if (c) c.width = c.height = 0;
}

// Decodes with EXIF orientation applied, so a portrait phone photo is edited
// upright, and caps the longest edge so a 12 MP photo stays bounded in memory.
export async function decodeImage(file: Blob): Promise<HTMLCanvasElement> {
  const bitmap = await createImageBitmap(file, { imageOrientation: 'from-image' });
  const scale = Math.min(1, maxEdge / Math.max(bitmap.width, bitmap.height));
  const out = canvas(Math.round(bitmap.width * scale), Math.round(bitmap.height * scale));
  const ctx = context(out);
  ctx.imageSmoothingQuality = 'high';
  ctx.drawImage(bitmap, 0, 0, out.width, out.height);
  bitmap.close();
  return out;
}

// A brand-new file rendered from the decoded pixels plus the boxes: no layers,
// and no metadata (EXIF, GPS) because nothing is copied from the source file.
export async function renderRedacted(
  source: HTMLCanvasElement,
  boxes: NRect[],
  type: 'image/png' | 'image/jpeg' = 'image/png',
): Promise<Blob> {
  const out = canvas(source.width, source.height);
  const ctx = context(out);
  ctx.drawImage(source, 0, 0);
  ctx.fillStyle = redactionFill;
  for (const b of boxes) {
    const p = toPixelRect(b, out.width, out.height);
    ctx.fillRect(p.x, p.y, p.w, p.h);
  }
  const blob = await new Promise<Blob | null>((resolve) => out.toBlob(resolve, type, 0.92));
  release(out);
  if (!blob) throw new CanvasError();
  return blob;
}

// Decodes the exported file itself — not the canvas it came from — and checks
// every box is black in it.
export async function verifyRedacted(
  file: Blob,
  width: number,
  height: number,
  boxes: NRect[],
  check: { tolerance?: number; inset?: number } = {},
): Promise<boolean> {
  const bitmap = await createImageBitmap(file, { premultiplyAlpha: 'none', colorSpaceConversion: 'none' });
  try {
    if (bitmap.width !== width || bitmap.height !== height) return false;
    const c = canvas(width, height);
    const ctx = context(c);
    ctx.drawImage(bitmap, 0, 0);
    const ok = boxesAreBlack(ctx.getImageData(0, 0, width, height).data, width, height, boxes, check);
    release(c);
    return ok;
  } finally {
    bitmap.close();
  }
}
