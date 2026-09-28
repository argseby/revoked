import { describe, expect, it } from 'vitest';
import { boxesAreBlack, toPixelRect } from '../src/lib/redaction/geometry';
import { buildPdf } from '../src/lib/redaction/pdf-writer';
import { findMatches } from '../src/lib/redaction/text-search';

describe('findMatches', () => {
  const runs = [
    { str: 'IBAN: DE89 3704 0044 0532 0130 00', x: 0.1, y: 0.5, w: 0.6, h: 0.02 },
    { str: 'Steuer-ID 12345678901', x: 0.1, y: 0.6, w: 0.3, h: 0.02 },
  ];

  it('boxes every occurrence, case-insensitively, over the matching characters', () => {
    const [box] = findMatches(runs, 'de89');
    const perChar = 0.6 / runs[0].str.length;
    expect(box.x).toBeLessThanOrEqual(0.1 + perChar * 6);
    expect(box.x + box.w).toBeGreaterThanOrEqual(0.1 + perChar * 10);
    expect(box.y).toBeLessThan(0.5);
    expect(box.y + box.h).toBeGreaterThan(0.52);
  });

  it('finds repeats and ignores blank terms', () => {
    expect(findMatches([{ str: 'aa aa', x: 0, y: 0, w: 1, h: 0.1 }], 'aa')).toHaveLength(2);
    expect(findMatches(runs, '   ')).toEqual([]);
    expect(findMatches(runs, 'nothing')).toEqual([]);
  });

  it('stays on the page', () => {
    for (const b of findMatches([{ str: 'edge', x: 0, y: 0, w: 1, h: 0.05 }], 'edge')) {
      expect(b.x).toBeGreaterThanOrEqual(0);
      expect(b.y).toBeGreaterThanOrEqual(0);
      expect(b.x + b.w).toBeLessThanOrEqual(1);
    }
  });
});

describe('buildPdf', () => {
  const jpeg = new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3, 0xff, 0xd9]);
  const pdf = buildPdf([
    { jpeg, pixelWidth: 1654, pixelHeight: 2339, width: 595.28, height: 841.89 },
    { jpeg, pixelWidth: 2339, pixelHeight: 1654, width: 841.89, height: 595.28 },
  ]);
  const text = new TextDecoder('latin1').decode(pdf);

  it('is a PDF with one image page per input', () => {
    expect(text.startsWith('%PDF-1.4')).toBe(true);
    expect(text.trimEnd().endsWith('%%EOF')).toBe(true);
    expect(text).toContain('/Count 2');
    expect(text.match(/\/Subtype \/Image/g)).toHaveLength(2);
    expect(text).toContain('/MediaBox [0 0 841.89 595.28]');
  });

  it('has an xref whose every offset lands on its object', () => {
    const xrefAt = Number(/startxref\n(\d+)/.exec(text)![1]);
    expect(text.slice(xrefAt, xrefAt + 4)).toBe('xref');
    const entries = text.slice(xrefAt).split('\n').slice(3).filter((l) => / n $/.test(l));
    entries.forEach((line, i) => {
      const at = Number(line.slice(0, 10));
      expect(text.slice(at, at + `${i + 1} 0 obj`.length)).toBe(`${i + 1} 0 obj`);
    });
    expect(entries).toHaveLength(2 + 2 * 3);
  });

  it('embeds the JPEG bytes unchanged', () => {
    const at = text.indexOf('stream\n', text.indexOf('/DCTDecode')) + 'stream\n'.length;
    expect(Array.from(pdf.slice(at, at + jpeg.length))).toEqual(Array.from(jpeg));
  });
});

describe('boxesAreBlack with JPEG tolerance', () => {
  const w = 64;
  const h = 64;
  const box = { x: 0.25, y: 0.25, w: 0.5, h: 0.5 };

  function page(fill: (x: number, y: number) => number) {
    const px = new Uint8ClampedArray(w * h * 4);
    for (let y = 0; y < h; y++)
      for (let x = 0; x < w; x++) {
        const v = fill(x, y);
        px.set([v, v, v, 255], (y * w + x) * 4);
      }
    return px;
  }

  it('accepts near-black with ringing along the edge', () => {
    const p = toPixelRect(box, w, h);
    const px = page((x, y) => {
      const inside = x >= p.x && x < p.x + p.w && y >= p.y && y < p.y + p.h;
      if (!inside) return 255;
      const edge = x === p.x || y === p.y || x === p.x + p.w - 1 || y === p.y + p.h - 1;
      return edge ? 90 : 12;
    });
    expect(boxesAreBlack(px, w, h, [box])).toBe(false);
    expect(boxesAreBlack(px, w, h, [box], { tolerance: 24, inset: 3 })).toBe(true);
  });

  it('still rejects a box that is not there', () => {
    expect(boxesAreBlack(page(() => 255), w, h, [box], { tolerance: 24, inset: 3 })).toBe(false);
  });
});
