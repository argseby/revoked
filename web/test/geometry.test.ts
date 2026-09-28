import { describe, expect, it } from 'vitest';
import { boxesAreBlack, rectFromPoints, toPixelRect, translate } from '../src/lib/redaction/geometry';

function image(w: number, h: number, fill: [number, number, number, number]) {
  const px = new Uint8ClampedArray(w * h * 4);
  for (let i = 0; i < px.length; i += 4) px.set(fill, i);
  return px;
}

function paint(px: Uint8ClampedArray, w: number, r: { x: number; y: number; w: number; h: number }) {
  for (let y = r.y; y < r.y + r.h; y++) for (let x = r.x; x < r.x + r.w; x++) px.set([0, 0, 0, 255], (y * w + x) * 4);
}

describe('toPixelRect', () => {
  it('rounds outward, never inward', () => {
    expect(toPixelRect({ x: 0.1049, y: 0.2051, w: 0.1, h: 0.1 }, 100, 100)).toEqual({ x: 10, y: 20, w: 11, h: 11 });
  });

  it('keeps an exact box exact', () => {
    expect(toPixelRect({ x: 0.25, y: 0.5, w: 0.5, h: 0.25 }, 200, 100)).toEqual({ x: 50, y: 50, w: 100, h: 25 });
  });

  it('clamps to the image', () => {
    expect(toPixelRect({ x: -0.1, y: 0.9, w: 0.3, h: 0.5 }, 100, 50)).toEqual({ x: 0, y: 45, w: 20, h: 5 });
  });
});

describe('rectFromPoints', () => {
  it('normalises a drag in any direction and clamps to the image', () => {
    expect(rectFromPoints({ x: 0.8, y: 1.2 }, { x: 0.2, y: 0.4 })).toEqual({ x: 0.2, y: 0.4, w: 0.6000000000000001, h: 0.6 });
  });
});

describe('translate', () => {
  it('stops at the edges', () => {
    expect(translate({ x: 0.8, y: 0.1, w: 0.2, h: 0.2 }, 0.5, -0.5)).toEqual({ x: 0.8, y: 0, w: 0.2, h: 0.2 });
  });
});

describe('boxesAreBlack', () => {
  const box = { x: 0.2, y: 0.3, w: 0.25, h: 0.1 };

  it('accepts an export whose boxes are covered', () => {
    const px = image(64, 48, [255, 255, 255, 255]);
    paint(px, 64, toPixelRect(box, 64, 48));
    expect(boxesAreBlack(px, 64, 48, [box])).toBe(true);
  });

  it('rejects an export with a missing box', () => {
    const px = image(64, 48, [255, 255, 255, 255]);
    paint(px, 64, toPixelRect(box, 64, 48));
    expect(boxesAreBlack(px, 64, 48, [box, { x: 0.6, y: 0.6, w: 0.2, h: 0.2 }])).toBe(false);
  });

  it('rejects a box that stops a row short', () => {
    const px = image(64, 48, [255, 255, 255, 255]);
    const p = toPixelRect(box, 64, 48);
    paint(px, 64, { ...p, h: p.h - 1 });
    expect(boxesAreBlack(px, 64, 48, [box])).toBe(false);
  });

  it('rejects translucent black', () => {
    const px = image(8, 8, [0, 0, 0, 200]);
    expect(boxesAreBlack(px, 8, 8, [{ x: 0, y: 0, w: 1, h: 1 }])).toBe(false);
  });
});
