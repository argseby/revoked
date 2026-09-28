import type { Action } from 'svelte/action';

// Marks the element `data-inview` the first time it scrolls into sight, so a
// CSS animation starts when someone can actually see it.
export const inview: Action<HTMLElement> = (node) => {
  if (!('IntersectionObserver' in window)) {
    node.dataset.inview = '';
    return;
  }
  const io = new IntersectionObserver(
    (entries) => {
      if (entries.some((e) => e.isIntersecting)) {
        node.dataset.inview = '';
        io.disconnect();
      }
    },
    { threshold: 0.35 },
  );
  io.observe(node);
  return { destroy: () => io.disconnect() };
};
