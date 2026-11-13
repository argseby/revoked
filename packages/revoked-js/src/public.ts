import { ClientContext } from './core/context.js';
import { Transport, type TransportOptions } from './core/transport.js';
import { Grants, type GrantCache } from './resources/grants.js';
import { Public } from './resources/public.js';

export {
  Public,
  PublicLinks,
  PublicRequests,
  PublicInvites,
  PublicAttestations,
  type ProvenIdentity,
  type OpenShareOptions,
  type SubmitAnswerOptions,
  type SubmittedAnswer,
} from './resources/public.js';
export { Grants, type GrantRef, type GrantValue, type GrantStatus, type GrantCache } from './resources/grants.js';
export type { SharePreview, OpenedShare, SharedRecord, SharedSection, RequestPreview, Sharer, ServerClaim, Download } from './models.js';

export interface PublicClientOptions extends Omit<TransportOptions, 'credential'> {
  grantCache?: GrantCache;
}

/**
 * Calls that need no credential, for a server the caller does not sign in to:
 * opening shares, previewing requests, reading grants a sign-in handed over.
 */
export function createPublicClient(options: PublicClientOptions): Public & { grants: Grants } {
  const ctx = new ClientContext(new Transport(options));
  return Object.assign(new Public(ctx), { grants: new Grants(ctx, options.grantCache) });
}
