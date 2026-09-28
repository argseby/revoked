import { t } from './i18n.svelte';

export interface ConfirmRequest {
  title: string;
  message: string;
  action: string;
  cancel?: string;
  destructive?: boolean;
}

// One confirmation dialog for the whole app, resolved true or false.
class Confirm {
  request = $state<ConfirmRequest | null>(null);
  #resolve: ((ok: boolean) => void) | null = null;

  ask(r: ConfirmRequest): Promise<boolean> {
    this.#resolve?.(false);
    this.request = r;
    return new Promise((resolve) => (this.#resolve = resolve));
  }

  answer(ok: boolean) {
    this.#resolve?.(ok);
    this.#resolve = null;
    this.request = null;
  }
}

export const confirm = new Confirm();

class Toast {
  message = $state<string | null>(null);
  #timer: ReturnType<typeof setTimeout> | undefined;

  show(message: string) {
    clearTimeout(this.#timer);
    this.message = message;
    this.#timer = setTimeout(() => (this.message = null), 3500);
  }
}

export const toast = new Toast();

export async function copyText(text: string, message = t('common.copied')): Promise<boolean> {
  try {
    await navigator.clipboard.writeText(text);
    toast.show(message);
    return true;
  } catch {
    toast.show(t('common.copyBlocked'));
    return false;
  }
}
