// A share slug is the only key to the landlord page, so it comes from the
// CSPRNG and is long enough that guessing one is hopeless (CLAUDE.md #2).
const alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';

export function randomSlug(length = 20): string {
  const out: string[] = [];
  // Rejection sampling keeps every character equally likely.
  const limit = 256 - (256 % alphabet.length);
  while (out.length < length) {
    const bytes = crypto.getRandomValues(new Uint8Array(length * 2));
    for (const b of bytes) {
      if (b < limit) out.push(alphabet[b % alphabet.length]);
      if (out.length === length) break;
    }
  }
  return out.join('');
}
