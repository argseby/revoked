import { applications } from './applications.svelte';
import { labelFromFilename, redactedName } from './filename';
import { t } from './i18n.svelte';
import { canRedact, redaction } from './redaction/redaction.svelte';
import { keyForLabel } from './tenant';
import { stampableMimes, vault, type VaultRecord } from './vault.svelte';

export interface Target {
  key: string;
  label: string;
  hint?: string;
  redact?: boolean;
}

// Stages one file before it is uploaded, so it can be redacted first: the
// original is held only in this tab and is dropped, never sent, once a
// redacted copy replaces it (spec §4.1).
class Staging {
  open = $state(false);
  target = $state<Target | null>(null);
  newLabel = $state('');
  file = $state.raw<Blob | null>(null);
  filename = $state('');
  previewUrl = $state<string | null>(null);
  redacted = $state(false);
  uploading = $state(false);
  error = $state<string | null>(null);
  // Files dropped together wait here and open one after another.
  queue = $state.raw<File[]>([]);
  // Records created in this run, offered to open applications at the end.
  #added: VaultRecord[] = [];

  editorOpen = $state(false);
  // Set while redacting a file already on the server: Done replaces it there.
  replacing = $state<VaultRecord | null>(null);

  type = $derived(this.file?.type ?? '');
  isImage = $derived(this.type.startsWith('image/'));
  redactable = $derived(canRedact(this.type));
  stampable = $derived(stampableMimes.has(this.type));
  needsLabel = $derived(this.target === null);
  canUpload = $derived(!!this.file && !this.uploading && (!this.needsLabel || this.newLabel.trim().length > 0));

  begin(target: Target | null) {
    this.#clear();
    this.target = target;
    this.open = true;
  }

  // Dropped straight onto a slot, or anywhere with no slot (target null).
  drop(target: Target | null, files: File[]) {
    if (!files.length) return;
    const [first, ...rest] = files;
    this.begin(target);
    this.pick(first);
    this.queue = target ? [] : rest;
  }

  pick(file: File) {
    this.#setFile(file, file.name, false);
    if (this.needsLabel && !this.newLabel.trim()) this.newLabel = labelFromFilename(file.name);
  }

  async redact() {
    if (!this.file) return;
    if (await redaction.load(this.file)) this.editorOpen = true;
    else this.error = redaction.error;
  }

  // Asks nothing: the caller has already confirmed that the unredacted
  // original will be deleted from the server.
  async redactExisting(r: VaultRecord) {
    this.error = null;
    const blob = await vault.fetchBytes(r);
    if (!blob) {
      this.error = vault.error;
      return;
    }
    const typed = blob.type ? blob : new Blob([blob], { type: r.mime ?? '' });
    this.replacing = r;
    this.filename = r.filename ?? r.key;
    if (await redaction.load(typed)) this.editorOpen = true;
    else {
      this.error = redaction.error;
      this.replacing = null;
    }
  }

  async applyRedaction(out: Blob) {
    const name = redactedName(this.filename, out.type);
    this.editorOpen = false;
    redaction.reset();
    const existing = this.replacing;
    if (existing) {
      this.replacing = null;
      const res = await vault.uploadFile(existing.key, existing.label, out, name);
      this.error = res.ok ? null : vault.error;
      return;
    }
    this.#setFile(out, name, true);
  }

  cancelEditor() {
    this.editorOpen = false;
    this.replacing = null;
    redaction.reset();
  }

  async upload(): Promise<boolean> {
    if (!this.file || !this.canUpload) return false;
    this.uploading = true;
    this.error = null;
    const label = this.target?.label ?? this.newLabel.trim();
    const key = this.target?.key ?? keyForLabel(label, new Set(vault.records.map((r) => r.key)));
    const res = await vault.uploadFile(key, label, this.file, this.filename);
    this.uploading = false;
    if (!res.ok) {
      this.error = vault.error ?? t('error.generic');
      return false;
    }
    if (res.added && res.record) this.#added.push(res.record);
    this.#next();
    return true;
  }

  close() {
    this.queue = [];
    this.open = false;
    this.#clear();
    const added = this.#added;
    this.#added = [];
    if (added.length) void applications.offer(added);
  }

  #next() {
    const [next, ...rest] = this.queue;
    if (!next) {
      this.close();
      return;
    }
    this.#clear();
    this.queue = rest;
    this.pick(next);
  }

  #setFile(file: Blob, name: string, redacted: boolean) {
    if (this.previewUrl) URL.revokeObjectURL(this.previewUrl);
    this.file = file;
    this.filename = name;
    this.redacted = redacted;
    this.error = null;
    this.previewUrl = file.type.startsWith('image/') ? URL.createObjectURL(file) : null;
  }

  #clear() {
    if (this.previewUrl) URL.revokeObjectURL(this.previewUrl);
    this.newLabel = '';
    this.file = null;
    this.filename = '';
    this.previewUrl = null;
    this.redacted = false;
    this.uploading = false;
    this.error = null;
  }
}

export const staging = new Staging();

class Preview {
  record = $state<VaultRecord | null>(null);
  url = $state<string | null>(null);
  mime = $state('');
  loading = $state(false);
  error = $state<string | null>(null);

  async show(r: VaultRecord) {
    this.close();
    this.record = r;
    this.loading = true;
    const blob = await vault.fetchBytes(r);
    this.loading = false;
    if (!blob) {
      this.error = vault.error ?? t('preview.failed');
      return;
    }
    this.mime = blob.type || r.mime || '';
    this.url = URL.createObjectURL(blob);
  }

  close() {
    if (this.url) URL.revokeObjectURL(this.url);
    this.record = null;
    this.url = null;
    this.mime = '';
    this.error = null;
  }
}

export const preview = new Preview();
