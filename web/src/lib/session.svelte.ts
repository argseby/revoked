import { ApiClient, ApiError } from './api';
import { t } from './i18n.svelte';

export interface User {
  id: string;
  email: string;
  name?: string;
  activeWorkspace: string;
}

interface AuthResponse {
  token: string;
  record: User;
}

interface Stored {
  server: string;
  token: string;
  user: User;
}

const storageKey = 'revoked.web.session';
const serverKey = 'revoked.web.server';

// The hosted service. An operator's /config.json can name another default,
// and can forbid choosing a server at all.
export const hostedServer = 'https://api.revoked.link';

function readStored(): Stored | null {
  try {
    const raw = localStorage.getItem(storageKey);
    return raw ? (JSON.parse(raw) as Stored) : null;
  } catch {
    return null;
  }
}

function writeStored(s: Stored | null) {
  try {
    if (s) localStorage.setItem(storageKey, JSON.stringify(s));
    else localStorage.removeItem(storageKey);
  } catch {
    /* storage unavailable: the session lasts as long as the tab */
  }
}

export function normaliseServer(input: string, fallback = hostedServer): string {
  const trimmed = input.trim().replace(/\/+$/, '');
  if (!trimmed) return fallback;
  return /^https?:\/\//i.test(trimmed) ? trimmed : `https://${trimmed}`;
}

export function serverHost(server: string): string {
  try {
    return new URL(server).host;
  } catch {
    return server;
  }
}

function readServer(): string | null {
  try {
    return localStorage.getItem(serverKey);
  } catch {
    return null;
  }
}

function writeServer(server: string | null) {
  try {
    if (server) localStorage.setItem(serverKey, server);
    else localStorage.removeItem(serverKey);
  } catch {
    /* not remembered */
  }
}

class Session {
  server = $state(hostedServer);
  defaultServer = $state(hostedServer);
  canChangeServer = $state(true);
  token = $state<string | null>(null);
  user = $state<User | null>(null);
  ready = $state(false);
  busy = $state(false);
  error = $state<string | null>(null);

  #client: ApiClient | null = null;
  #clientBase = '';

  get api(): ApiClient {
    if (!this.#client || this.#clientBase !== this.server) {
      this.#clientBase = this.server;
      this.#client = new ApiClient({
        base: this.server,
        token: () => this.token,
        onUnauthorized: () => this.signOut(),
      });
    }
    return this.#client;
  }

  get workspace(): string {
    return this.user?.activeWorkspace ?? '';
  }

  async init() {
    try {
      const res = await fetch('/config.json', { cache: 'no-store' });
      if (res.ok) {
        const cfg = (await res.json()) as { server?: string; customServers?: boolean };
        if (cfg.server) this.defaultServer = normaliseServer(cfg.server);
        if (cfg.customServers === false) this.canChangeServer = false;
      }
    } catch {
      /* no config: the hosted service, changeable */
    }
    const chosen = this.canChangeServer ? readServer() : null;
    this.server = chosen ? normaliseServer(chosen, this.defaultServer) : this.defaultServer;

    const stored = readStored();
    if (stored && (this.canChangeServer || stored.server === this.server)) {
      this.server = stored.server;
      this.token = stored.token;
      this.user = stored.user;
      await this.refresh();
    }
    this.ready = true;
  }

  async signIn(server: string, email: string, password: string): Promise<boolean> {
    this.busy = true;
    this.error = null;
    try {
      if (this.canChangeServer) this.server = normaliseServer(server, this.defaultServer);
      const data = await this.api.post<AuthResponse>('/api/collections/users/auth-with-password', {
        identity: email.trim(),
        password,
      });
      this.#accept(data);
      writeServer(this.server === this.defaultServer ? null : this.server);
      return true;
    } catch (e) {
      this.error =
        e instanceof ApiError && e.status === 400
          ? t('login.wrong')
          : e instanceof ApiError && e.code === 'network'
            ? t('login.unreachable', { server: this.server })
            : e instanceof Error
              ? e.message
              : t('login.failed');
      return false;
    } finally {
      this.busy = false;
    }
  }

  signOut() {
    this.token = null;
    this.user = null;
    writeStored(null);
  }

  async refresh() {
    try {
      this.#accept(await this.api.post<AuthResponse>('/api/collections/users/auth-refresh'));
    } catch (e) {
      // Only the server saying no ends the session; being offline does not.
      if (e instanceof ApiError && (e.status === 401 || e.status === 403)) this.signOut();
    }
  }

  #accept(data: AuthResponse) {
    this.token = data.token;
    this.user = data.record;
    writeStored({ server: this.server, token: data.token, user: data.record });
  }
}

export const session = new Session();
