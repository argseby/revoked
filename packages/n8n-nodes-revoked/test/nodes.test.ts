import { createHmac } from 'node:crypto';
import type { IWebhookFunctions } from 'n8n-workflow';
import { describe, expect, it, vi } from 'vitest';
import { compact, ids } from '../nodes/Revoked/shared';
import { Revoked } from '../nodes/Revoked/Revoked.node';
import { RevokedTrigger } from '../nodes/RevokedTrigger/RevokedTrigger.node';
import { toSchema } from '../nodes/Revoked/resources/template';

const secret = 'whsec_test_secret';

function signed(body: string, key = secret, at = Math.floor(Date.now() / 1000)): string {
	return `t=${at},v1=${createHmac('sha256', key).update(`${at}.${body}`).digest('hex')}`;
}

function webhookContext(body: string, signature: string | undefined, state: Record<string, unknown>) {
	const response = { status: vi.fn().mockReturnThis(), end: vi.fn() };
	const ctx = {
		getRequestObject: () => ({
			rawBody: Buffer.from(body),
			header: (name: string) => (name.toLowerCase() === 'revoked-signature' ? signature : undefined),
		}),
		getResponseObject: () => response,
		getWorkflowStaticData: () => state,
		getNodeParameter: (_: string, fallback: unknown) => fallback,
		helpers: { returnJsonArray: (data: unknown) => [{ json: data }] },
	} as unknown as IWebhookFunctions;
	return { ctx, response };
}

const event = JSON.stringify({
	id: 'evt_1',
	type: 'response.submitted',
	created: '2026-11-14T12:00:00Z',
	workspace: 'ws1',
	data: { object: 'response', id: 'lnk1', request: 'req1', status: 'active' },
});

describe('trigger', () => {
	const trigger = new RevokedTrigger();

	it('emits a delivery signed with the endpoint secret', async () => {
		const { ctx } = webhookContext(event, signed(event), { endpointId: 'ep1', endpointSecret: secret });
		const out = await trigger.webhook.call(ctx);
		expect(out.workflowData?.[0]?.[0]?.json).toMatchObject({ id: 'evt_1', type: 'response.submitted' });
	});

	it.each([
		['no signature', undefined, { endpointSecret: secret }],
		['another secret', signed(event, 'whsec_other'), { endpointSecret: secret }],
		['a stale timestamp', signed(event, secret, Math.floor(Date.now() / 1000) - 3600), { endpointSecret: secret }],
		['no stored secret', signed(event), {}],
	])('refuses a delivery with %s', async (_, signature, state) => {
		const { ctx, response } = webhookContext(event, signature, state);
		const out = await trigger.webhook.call(ctx);
		expect(out).toEqual({ noWebhookResponse: true });
		expect(response.status).toHaveBeenCalledWith(401);
	});

	it('offers every event type the SDK knows', () => {
		const events = trigger.description.properties.find((p) => p.name === 'events');
		expect(events?.options?.length).toBeGreaterThan(20);
	});
});

describe('helpers', () => {
	it('drops fields left empty', () => {
		expect(compact({ a: '', b: 0, c: false, d: undefined, e: 'x' })).toEqual({ b: 0, c: false, e: 'x' });
	});

	it('reads ids from a list or a comma-separated string', () => {
		expect(ids(['a', 'b'])).toEqual(['a', 'b']);
		expect(ids(' a, b ,,c')).toEqual(['a', 'b', 'c']);
		expect(ids(undefined)).toEqual([]);
	});
});

describe('action node', () => {
	const properties = new Revoked().description.properties;
	const resources = (properties.find((p) => p.name === 'resource')?.options ?? []) as Array<{ value: string }>;

	it('gives every resource its operations, each with an action', () => {
		for (const { value } of resources) {
			const operation = properties.find(
				(p) => p.name === 'operation' && p.displayOptions?.show?.resource?.includes(value),
			);
			expect(operation, value).toBeDefined();
			for (const option of operation?.options ?? []) expect(option).toHaveProperty('action');
		}
	});

	it('offers no way to send to a contact', () => {
		const contactOps = properties.find(
			(p) => p.name === 'operation' && p.displayOptions?.show?.resource?.includes('contact'),
		);
		const values = (contactOps?.options ?? []).map((o) => (o as { value: string }).value);
		expect(values).not.toContain('send');
		expect(values).not.toContain('ask');
	});
});

describe('template fields', () => {
	it('sends a list of fields as records, the shape the request page reads', () => {
		expect(toSchema([{ key: 'city' }])).toEqual({ records: [{ key: 'city' }] });
	});

	it('passes a full schema on unchanged', () => {
		const schema = { records: [{ key: 'city' }], sections: [{ key: 'address', records: [] }] };
		expect(toSchema(schema)).toBe(schema);
	});
});
