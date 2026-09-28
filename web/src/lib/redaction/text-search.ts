import type { NRect } from './geometry';

// A run of text on a page, normalised like the boxes (0..1 of the page).
export interface TextRun {
  str: string;
  x: number;
  y: number;
  w: number;
  h: number;
}

// Boxes over every occurrence of `term` inside a run. A run's glyph widths are
// unknown, so the match is placed proportionally and padded — generous on
// purpose, since a box that is too wide costs nothing and one too narrow
// leaves a digit showing.
export function findMatches(runs: TextRun[], term: string): NRect[] {
  const needle = term.trim().toLowerCase();
  if (!needle) return [];
  const out: NRect[] = [];
  for (const r of runs) {
    const hay = r.str.toLowerCase();
    if (!hay.length) continue;
    const perChar = r.w / hay.length;
    for (let i = hay.indexOf(needle); i !== -1; i = hay.indexOf(needle, i + needle.length)) {
      const padX = perChar * 0.6;
      const padY = r.h * 0.25;
      const x = Math.max(0, r.x + perChar * i - padX);
      const y = Math.max(0, r.y - padY);
      out.push({
        x,
        y,
        w: Math.min(1 - x, perChar * needle.length + 2 * padX),
        h: Math.min(1 - y, r.h + 2 * padY),
      });
    }
  }
  return out;
}
