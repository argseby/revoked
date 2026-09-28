import type { Action } from 'svelte/action';

export interface DropOptions {
  ondrop: (files: File[]) => void;
  disabled?: boolean;
}

function hasFiles(e: DragEvent): boolean {
  return !!e.dataTransfer && Array.from(e.dataTransfer.types).includes('Files');
}

// Accepts files dragged onto the element and marks it with `data-dragging`
// while they hover, for styling. Nested zones win: the innermost handles the
// drop and the event goes no further.
export const dropFiles: Action<HTMLElement, DropOptions> = (node, initial) => {
  let opts = initial;
  // dragenter/dragleave also fire for every child crossed, so count them.
  let depth = 0;

  const set = (on: boolean) => {
    if (on) node.dataset.dragging = '';
    else delete node.dataset.dragging;
  };

  const enter = (e: DragEvent) => {
    if (opts.disabled || !hasFiles(e)) return;
    e.preventDefault();
    e.stopPropagation();
    depth++;
    set(true);
  };
  const over = (e: DragEvent) => {
    if (opts.disabled || !hasFiles(e)) return;
    e.preventDefault();
    e.stopPropagation();
    if (e.dataTransfer) e.dataTransfer.dropEffect = 'copy';
  };
  const leave = (e: DragEvent) => {
    if (opts.disabled || !hasFiles(e)) return;
    e.stopPropagation();
    depth = Math.max(0, depth - 1);
    if (depth === 0) set(false);
  };
  const drop = (e: DragEvent) => {
    if (opts.disabled || !hasFiles(e)) return;
    e.preventDefault();
    e.stopPropagation();
    depth = 0;
    set(false);
    const files = Array.from(e.dataTransfer?.files ?? []);
    if (files.length) opts.ondrop(files);
  };

  node.addEventListener('dragenter', enter);
  node.addEventListener('dragover', over);
  node.addEventListener('dragleave', leave);
  node.addEventListener('drop', drop);
  return {
    update(next) {
      opts = next;
      if (opts.disabled) {
        depth = 0;
        set(false);
      }
    },
    destroy() {
      node.removeEventListener('dragenter', enter);
      node.removeEventListener('dragover', over);
      node.removeEventListener('dragleave', leave);
      node.removeEventListener('drop', drop);
    },
  };
};
