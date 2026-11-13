import { describe, expect, it } from 'vitest';
import { GoneError, PermissionError, Revoked, ValidationError } from '../../src/index.js';
import { generateIdentityKey } from '../../src/identity.js';
import { fingerprintPem, verifyIdentityStatus, verifyParentSignature, verifyServerAssertion } from '../../src/trust.js';

const server = process.env.REVOKED_SERVER;
const session = process.env.REVOKED_SESSION;
const responderSession = process.env.REVOKED_RESPONDER_SESSION;
const run = server && session && responderSession ? describe : describe.skip;

run('against a real server', () => {
  const owner = new Revoked({ server: server!, session: session! });
  const responder = new Revoked({ server: server!, session: responderSession! });
  const anonymous = new Revoked({ server: server! });

  it('verifies the server assertion Go signed', async () => {
    const info = await anonymous.server.info();
    const body = await verifyServerAssertion(info.assertion);
    expect(body.fingerprint).toBe(info.fingerprint);
    expect(await fingerprintPem(info.publicKey)).toBe(info.fingerprint);
    expect((await anonymous.server.permissions()).map((p) => p.key)).toContain('shares:manage');
  });

  it('shares a record and reads it back as a recipient', async () => {
    const workspace = await owner.workspace();
    expect(workspace).toBeTruthy();
    const record = await owner.records.create({ key: `email_${Date.now()}`, label: 'Email', value: 'ada@example.com' });
    const link = await owner.links.create({ label: 'Email', records: [record.id], maxViews: 2 });
    expect(link.slug).toBeTruthy();

    const preview = await anonymous.public.links.preview(link.slug);
    expect(preview.requiresPassword).toBe(false);
    const opened = await anonymous.public.links.open(link.slug);
    expect(opened.records.find((r) => r.id === record.id)?.value).toBe('ada@example.com');

    await owner.records.update(record.id, { value: 'ada@new.example' });
    const again = await anonymous.public.links.open(link.slug);
    expect(again.records.find((r) => r.id === record.id)?.value).toBe('ada@new.example');

    const third = await anonymous.public.links.open(link.slug).catch((e: unknown) => e);
    expect(third).toBeInstanceOf(GoneError);
  });

  it('refuses a revoked share with a typed error', async () => {
    const record = await owner.records.create({ key: `phone_${Date.now()}`, label: 'Phone', value: '+49 30 1234' });
    const link = await owner.links.create({ label: 'Phone', records: [record.id] });
    await owner.links.revoke(link.id);
    const error = await anonymous.public.links.open(link.slug).catch((e: unknown) => e);
    expect(error).toBeInstanceOf(GoneError);
    expect((error as GoneError).code).toBe('link_revoked');
  });

  it('opens a handshake-gated share with a proven identity and checks the chain', async () => {
    const key = await generateIdentityKey();
    const identity = await owner.identities.createFromKey(key, { name: 'SDK test' });
    expect(identity.fingerprint).toMatch(/^[0-9a-f]{64}$/);

    const info = await anonymous.server.info();
    expect(await verifyParentSignature(info.publicKey, identity.fingerprint, identity.parentSignature)).toBe(true);
    const status = await verifyIdentityStatus(
      await anonymous.server.identityStatus(identity.fingerprint),
      info.publicKey,
      info.domain,
      identity.fingerprint,
    );
    expect(status.status).toBe('active');

    const record = await owner.records.create({ key: `iban_${Date.now()}`, label: 'IBAN', value: 'DE00 1234' });
    const link = await owner.links.create({ label: 'IBAN', records: [record.id], identity: identity.id, requireHandshake: true });

    const refused = await anonymous.public.links.open(link.slug).catch((e: unknown) => e);
    expect(refused).toBeInstanceOf(Error);

    const opened = await anonymous.public.links.open(link.slug, { identity: { id: identity.id, key } });
    expect(opened.records[0]?.value).toBe('DE00 1234');
    expect(opened.handshakeToken).toBeTruthy();

    const reused = await anonymous.public.links.open(link.slug, {
      identity: { id: identity.id, key, handshakeToken: opened.handshakeToken! },
    });
    expect(reused.records[0]?.value).toBe('DE00 1234');
  });

  it('works with an API key it created, bound to the workspace', async () => {
    const workspace = await owner.workspace();
    const { token, key } = await owner.apiKeys.create({ label: 'SDK test', permissions: ['shares:read', 'shares:manage'] });
    expect(key.id).toBeTruthy();
    const withKey = new Revoked({ server: server!, apiKey: token });
    expect(await withKey.workspace()).toBe(workspace);
    expect((await withKey.me()).kind).toBe('apiKey');
    const list = await withKey.links.list({ perPage: 5 });
    expect(Array.isArray(list.items)).toBe(true);

    const denied = await withKey.records.create({ key: 'x', label: 'x', value: 'y' }).catch((e: unknown) => e);
    expect(denied instanceof PermissionError || denied instanceof ValidationError).toBe(true);
    await owner.apiKeys.delete(key.id);
  });

  it('collects an answer to a request from another account', async () => {
    const key = await generateIdentityKey();
    const identity = await owner.identities.createFromKey(key, { name: 'Requests' });
    const request = await owner.requests.create({ label: 'Contact', identity: identity.id, allowExtraFields: true, maxResponses: 5 });
    expect(request.slug).toMatch(/^[a-z0-9]{24}$/);
    const preview = await anonymous.public.requests.preview(request.slug);
    expect(preview.label).toBe('Contact');

    await responder.public.requests.submit(request.slug, { data: { email: 'grace@example.com' }, senderName: 'Grace' });
    const responses = await owner.requests.responses(request.id);
    expect(responses).toHaveLength(1);
    expect(responses[0]?.senderName).toBe('Grace');

    const { token, key: apiKey } = await owner.apiKeys.create({ label: 'Answers', permissions: ['requests:read', 'responses:read'] });
    const viaKey = await new Revoked({ server: server!, apiKey: token }).requests.responses(request.id);
    expect(viaKey).toHaveLength(1);
    await owner.apiKeys.delete(apiKey.id);

    await owner.requests.close(request.id);
    const closed = await responder.public.requests.submit(request.slug, { data: { email: 'x' } }).catch((e: unknown) => e);
    expect(closed).toBeInstanceOf(Error);
  });

  it('lists the webhook catalogue', async () => {
    const { items } = await owner.webhooks.eventTypes();
    expect(items.map((i) => i.type)).toContain('link.revoked');
  });
});
