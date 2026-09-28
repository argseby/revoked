export function formatBytes(n: number): string {
  if (n < 1024) return `${n} B`;
  const units = ['KB', 'MB', 'GB'];
  let i = -1;
  do {
    n /= 1024;
    i++;
  } while (n >= 1024 && i < units.length - 1);
  return `${n.toFixed(n >= 100 ? 0 : 1)} ${units[i]}`;
}

// PocketBase writes "2026-09-28 10:11:12.000Z" — a space, not a "T".
export function parseServerDate(s: string): Date {
  return new Date(s.replace(' ', 'T'));
}

export function daysUntil(iso: string, now = new Date()): number {
  return Math.ceil((parseServerDate(iso).getTime() - now.getTime()) / 86_400_000);
}
