// Boxes are stored normalised (0..1 of the image's width and height), so the
// on-screen size of the editor never matters; they become pixels only here.

export interface Point {
  x: number;
  y: number;
}

export interface NRect {
  x: number;
  y: number;
  w: number;
  h: number;
}

export interface PxRect {
  x: number;
  y: number;
  w: number;
  h: number;
}

export const minBoxSide = 0.01;

const clamp01 = (v: number) => Math.min(1, Math.max(0, v));

export function rectFromPoints(a: Point, b: Point): NRect {
  const x1 = clamp01(Math.min(a.x, b.x));
  const y1 = clamp01(Math.min(a.y, b.y));
  const x2 = clamp01(Math.max(a.x, b.x));
  const y2 = clamp01(Math.max(a.y, b.y));
  return { x: x1, y: y1, w: x2 - x1, h: y2 - y1 };
}

export function isLargeEnough(r: NRect): boolean {
  return r.w >= minBoxSide && r.h >= minBoxSide;
}

export function contains(r: NRect, p: Point): boolean {
  return p.x >= r.x && p.x <= r.x + r.w && p.y >= r.y && p.y <= r.y + r.h;
}

export function translate(r: NRect, dx: number, dy: number): NRect {
  return {
    x: Math.min(1 - r.w, Math.max(0, r.x + dx)),
    y: Math.min(1 - r.h, Math.max(0, r.y + dy)),
    w: r.w,
    h: r.h,
  };
}

export type Corner = 'nw' | 'ne' | 'sw' | 'se';

export function corners(r: NRect): Record<Corner, Point> {
  return {
    nw: { x: r.x, y: r.y },
    ne: { x: r.x + r.w, y: r.y },
    sw: { x: r.x, y: r.y + r.h },
    se: { x: r.x + r.w, y: r.y + r.h },
  };
}

export const opposite: Record<Corner, Corner> = { nw: 'se', ne: 'sw', sw: 'ne', se: 'nw' };

// Rounds outward, never inward: a rounding error must not leave a row or
// column of the covered pixels visible.
export function toPixelRect(n: NRect, width: number, height: number): PxRect {
  const left = Math.max(0, Math.floor(n.x * width));
  const top = Math.max(0, Math.floor(n.y * height));
  const right = Math.min(width, Math.ceil((n.x + n.w) * width));
  const bottom = Math.min(height, Math.ceil((n.y + n.h) * height));
  return { x: left, y: top, w: Math.max(0, right - left), h: Math.max(0, bottom - top) };
}

// Samples the centre and the four inner corners of every box in decoded RGBA
// pixels. A box that is not opaque black at any sample means the export did
// not cover what the reader saw, so the caller must keep nothing.
//
// A lossless PNG must be exactly black. A JPEG page is allowed `tolerance`
// and sampled `inset` pixels in, because the codec rings along a box's edge.
export function boxesAreBlack(
  rgba: ArrayLike<number>,
  width: number,
  height: number,
  boxes: NRect[],
  { tolerance = 0, inset = 0 }: { tolerance?: number; inset?: number } = {},
): boolean {
  for (const b of boxes) {
    const p = toPixelRect(b, width, height);
    if (p.w === 0 || p.h === 0) return false;
    const ix = Math.min(inset, Math.floor((p.w - 1) / 2));
    const iy = Math.min(inset, Math.floor((p.h - 1) / 2));
    const xs = [p.x + ix, p.x + Math.floor((p.w - 1) / 2), p.x + p.w - 1 - ix];
    const ys = [p.y + iy, p.y + Math.floor((p.h - 1) / 2), p.y + p.h - 1 - iy];
    const samples: [number, number][] = [
      [xs[1], ys[1]],
      [xs[0], ys[0]],
      [xs[2], ys[0]],
      [xs[0], ys[2]],
      [xs[2], ys[2]],
    ];
    for (const [x, y] of samples) {
      const i = (y * width + x) * 4;
      if (rgba[i] > tolerance || rgba[i + 1] > tolerance || rgba[i + 2] > tolerance || rgba[i + 3] !== 255) {
        return false;
      }
    }
  }
  return true;
}
