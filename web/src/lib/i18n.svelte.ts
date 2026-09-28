import { de } from './locales/de';
import { en, type Message, type MessageKey } from './locales/en';

export type Locale = 'en' | 'de';

const catalogues: Record<Locale, Record<MessageKey, Message>> = { en, de };
const storageKey = 'revoked.web.locale';

function detect(): Locale {
  try {
    const saved = localStorage.getItem(storageKey);
    if (saved === 'en' || saved === 'de') return saved;
  } catch {
    /* storage blocked: fall back to the browser */
  }
  return navigator.languages?.some((l) => l.toLowerCase().startsWith('de')) ? 'de' : 'en';
}

class I18n {
  locale = $state<Locale>(detect());

  constructor() {
    this.#apply();
  }

  toggle() {
    this.locale = this.locale === 'de' ? 'en' : 'de';
    try {
      localStorage.setItem(storageKey, this.locale);
    } catch {
      /* not remembered */
    }
    this.#apply();
  }

  #apply() {
    document.documentElement.lang = this.locale;
  }
}

export const i18n = new I18n();

// Reads i18n.locale, so any template or derived value calling it re-renders
// when the language changes.
export function t(key: MessageKey, params: Record<string, string | number> = {}): string {
  const m = catalogues[i18n.locale][key] ?? en[key];
  return typeof m === 'function' ? m(params) : m;
}

export function formatDate(iso: string | Date | undefined | null): string {
  if (!iso) return '';
  const d = typeof iso === 'string' ? new Date(iso.replace(' ', 'T')) : iso;
  if (Number.isNaN(d.getTime())) return '';
  return new Intl.DateTimeFormat(i18n.locale === 'de' ? 'de-DE' : 'en-GB', {
    day: 'numeric',
    month: 'short',
    year: 'numeric',
  }).format(d);
}
