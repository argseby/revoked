import {Easing, interpolate} from 'remotion';

export const FPS = 30;
export const WIDTH = 1920;
export const HEIGHT = 1080;

// The app's light palette (app/lib/core/design/app_colors.dart).
export const C = {
  paper: '#FAF9F6',
  white: '#FFFFFF',
  card: '#F2F0F6',
  sunken: '#E6E3EE',
  ink: '#16151F',
  muted: '#575569',
  border: '#7D798F',
  divider: '#E1DEE8',
  brand: '#3D35B5',
  brandTint: '#E9E6FB',
  onBrandTint: '#2A2390',
  success: '#1D6B4C',
  successTint: '#D7F0E3',
  warning: '#7A5600',
  warningTint: '#FFEFC9',
  danger: '#B42318',
  dangerTint: '#FCE4E1',
};

export const FONT = 'Inter, sans-serif';
export const MONO = '"Noto Sans Mono", monospace';

export const easeOut = Easing.bezier(0.22, 1, 0.36, 1);
export const easeInOut = Easing.bezier(0.65, 0, 0.35, 1);

/** 0 → 1 between `start` and `start + dur`, eased out. */
export const prog = (frame: number, start: number, dur = 18, easing = easeOut) =>
  interpolate(frame, [start, start + dur], [0, 1], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
    easing,
  });

/** Linear mix of two numbers. */
export const mix = (a: number, b: number, t: number) => a + (b - a) * t;

export const sec = (s: number) => Math.round(s * FPS);
