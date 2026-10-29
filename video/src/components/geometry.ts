export type Pt = {x: number; y: number};

/** Quadratic curve from `a` to `b`, bowed sideways by `bend` pixels. */
export const curve = (a: Pt, b: Pt, bend = 0) => {
  const mx = (a.x + b.x) / 2;
  const my = (a.y + b.y) / 2;
  const dx = b.x - a.x;
  const dy = b.y - a.y;
  const len = Math.hypot(dx, dy) || 1;
  const c = {x: mx - (dy / len) * bend, y: my + (dx / len) * bend};
  const at = (t: number): Pt => ({
    x: (1 - t) ** 2 * a.x + 2 * (1 - t) * t * c.x + t ** 2 * b.x,
    y: (1 - t) ** 2 * a.y + 2 * (1 - t) * t * c.y + t ** 2 * b.y,
  });
  const angle = (t: number) => {
    const tx = 2 * (1 - t) * (c.x - a.x) + 2 * t * (b.x - c.x);
    const ty = 2 * (1 - t) * (c.y - a.y) + 2 * t * (b.y - c.y);
    return (Math.atan2(ty, tx) * 180) / Math.PI;
  };
  return {d: `M ${a.x} ${a.y} Q ${c.x} ${c.y} ${b.x} ${b.y}`, at, angle, c};
};
