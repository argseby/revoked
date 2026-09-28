import { describeError } from './api';
import { session } from './session.svelte';
import type { VaultRecord } from './vault.svelte';

export type StampSource = { text: string } | { link: string };

// Shows files exactly as a landlord receives them: the server stamps them
// with the real stamper. A draft's stamp carries "#preview" in place of the
// link tag, so a preview copy can never pass for an application copy.
class StampPreview {
  files = $state<VaultRecord[]>([]);
  index = $state(0);
  source = $state<StampSource | null>(null);
  url = $state<string | null>(null);
  mime = $state('');
  loading = $state(false);
  error = $state<string | null>(null);

  open = $derived(this.source !== null);
  file = $derived(this.files[this.index] ?? null);

  show(files: VaultRecord[], source: StampSource) {
    this.close();
    this.files = files;
    this.source = source;
    void this.select(0);
  }

  async select(i: number) {
    const file = this.files[i];
    const source = this.source;
    if (!file || !source) return;
    this.index = i;
    this.#revoke();
    this.loading = true;
    this.error = null;
    try {
      const blob = await session.api.postForBlob('/api/stamp-preview', { record: file.id, ...source });
      if (this.source !== source || this.index !== i) return;
      this.mime = blob.type;
      this.url = URL.createObjectURL(blob);
    } catch (e) {
      if (this.index === i) this.error = describeError(e);
    } finally {
      if (this.index === i) this.loading = false;
    }
  }

  close() {
    this.#revoke();
    this.source = null;
    this.files = [];
    this.index = 0;
    this.error = null;
    this.loading = false;
  }

  #revoke() {
    if (this.url) URL.revokeObjectURL(this.url);
    this.url = null;
    this.mime = '';
  }
}

export const stampPreview = new StampPreview();
