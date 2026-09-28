export function stem(name: string): string {
  const s = name.replace(/\.[^./\\]+$/, '');
  return s || 'document';
}

// "gehaltsabrechnung_08-2026" → "Gehaltsabrechnung 08-2026": a starting name
// for a dropped file, which the reader can still change.
export function labelFromFilename(name: string): string {
  const s = stem(name).replace(/[_]+/g, ' ').replace(/\s+/g, ' ').trim();
  return s.charAt(0).toUpperCase() + s.slice(1);
}

// The redactor names every file it produces this way, so the name is what
// marks a stored file as redacted.
export function isRedacted(filename: string | undefined): boolean {
  return /-redacted\.(png|pdf)$/i.test(filename ?? '');
}

export function redactedName(original: string, type: string): string {
  return `${stem(original)}-redacted${type === 'application/pdf' ? '.pdf' : '.png'}`;
}
