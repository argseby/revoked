import type { NRect } from './geometry';

export interface RedactionPreset {
  name: string;
  boxes: NRect[];
}

// Starting boxes for common documents, normalised to a photo cropped to the
// card's edges. Add a preset only once it is measured on a real card photo
// (spec §4.7) — a guessed box that misses the number is worse than none,
// because it looks finished. The editor hides the menu while this is empty.
export const presets: RedactionPreset[] = [];
