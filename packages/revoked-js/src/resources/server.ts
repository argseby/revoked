import type { ClientContext } from '../core/context.js';
import { path } from '../core/context.js';
import type { CallOptions } from '../core/transport.js';
import type {
  Feature,
  FeaturePreset,
  IdentityCertificate,
  IdentityStatusAssertion,
  Permission,
  ServerCertificate,
  ServerInfo,
} from '../models.js';

/** What the server says about itself. Nothing here needs a credential. */
export class Server {
  constructor(private readonly ctx: ClientContext) {}

  /** Domain, version, root key, its signed assertion, and limits. Verify with `trust.verifyServer`. */
  info(options: CallOptions = {}): Promise<ServerInfo> {
    return this.ctx.transport.request('api/server', { signal: options.signal, anonymous: true });
  }

  /** The permission catalogue that API keys, members and tools are granted from. */
  async permissions(options: CallOptions = {}): Promise<Permission[]> {
    return (
      await this.ctx.transport.request<{ permissions: Permission[] }>('api/permissions', {
        signal: options.signal,
        anonymous: true,
      })
    ).permissions;
  }

  features(options: CallOptions = {}): Promise<{ features: Feature[]; presets: FeaturePreset[] }> {
    return this.ctx.transport.request('api/features', { signal: options.signal, anonymous: true });
  }

  /** True when the server answers its health check. */
  async health(options: CallOptions = {}): Promise<boolean> {
    try {
      await this.ctx.transport.request('healthz', { signal: options.signal, anonymous: true, responseType: 'text' });
      return true;
    } catch {
      return false;
    }
  }

  /** Domains this server refuses as callback and webhook targets. */
  async blockedDomains(options: CallOptions = {}): Promise<string[]> {
    const text = await this.ctx.transport.request<string>('api/blocked-domains', {
      signal: options.signal,
      anonymous: true,
      responseType: 'text',
    });
    return text
      .split('\n')
      .map((line) => line.trim())
      .filter((line) => line !== '' && !line.startsWith('#'));
  }

  /** The issuing certificate's public material. */
  certificate(options: CallOptions = {}): Promise<ServerCertificate> {
    return this.ctx.transport.request('api/certificate', { signal: options.signal, anonymous: true });
  }

  /** One identity's certificate and root signature. */
  identityCertificate(id: string, options: CallOptions = {}): Promise<IdentityCertificate> {
    return this.ctx.transport.request(path`api/certificate/${id}`, { signal: options.signal, anonymous: true });
  }

  /**
   * Has this server walk another domain's trust chain and report a verdict.
   * Trusts this server's answer; `verifyServer` and `verifySharer` from
   * `@kiunke.dev/revoked/trust` check the chain locally instead.
   */
  verifyPeer(
    input: { domain: string; identityFingerprint?: string; parentSignature?: string },
    options: CallOptions = {},
  ): Promise<{
    state: 'verified' | 'dnsMissing' | 'unverified' | 'spoofed' | 'revoked' | (string & {});
    domain: string;
    reason: string;
    rootFingerprint?: string;
    identityFingerprint?: string;
    identityStatus?: string;
  }> {
    return this.ctx.transport.request('api/verify-peer', { method: 'POST', body: input, anonymous: true, signal: options.signal });
  }

  /** The root-signed status statement for a fingerprint, unverified. Verify it with `verifyIdentityStatus` from `@kiunke.dev/revoked/trust`. */
  identityStatus(fingerprint: string, options: CallOptions = {}): Promise<IdentityStatusAssertion> {
    return this.ctx.transport.request(path`api/identities/${fingerprint}/status`, {
      signal: options.signal,
      anonymous: true,
    });
  }
}
