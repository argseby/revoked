import { t } from './i18n.svelte';
import type { MessageKey } from './locales/en';
import { tenantKeys } from './tenant';

// Template fields and slots are named in the reader's language; everything
// else by the label it was saved with.
export function recordName(r: { key: string; type: string; label: string }): string {
  if (tenantKeys.has(r.key)) return t((r.type === 'file' ? `slot.${r.key}` : `field.${r.key}`) as MessageKey);
  return r.label || r.key;
}
