import type { INodeProperties } from 'n8n-workflow';
import { NodeOperationError } from 'n8n-workflow';
import { compact } from '../shared';
import {
	asData,
	asList,
	collect,
	type Client,
	type Handler,
	idProperty,
	jsonParameter,
	limitOf,
	limitProperties,
	on,
	operationProperty,
	statusFilter,
	statusProperty,
} from '../fields';

const R = 'attestation';

export const attestationProperties: INodeProperties[] = [
	operationProperty(
		R,
		[
			{ name: 'Get', value: 'get', action: 'Get an attestation' },
			{ name: 'Get Many', value: 'getMany', action: 'Get many attestations' },
			{
				name: 'Issue',
				value: 'issue',
				action: 'Issue an attestation',
				description: 'Offer a signed statement to someone, in the name of the server’s domain',
			},
			{ name: 'Revoke', value: 'revoke', action: 'Revoke an attestation', description: 'This cannot be undone' },
		],
		'issue',
	),
	idProperty(R, 'attestationId', 'Attestation ID', ['get', 'revoke']),
	{
		displayName: 'Type',
		name: 'type',
		type: 'string',
		required: true,
		default: '',
		placeholder: 'verified_adult',
		description: 'A short key or a URI, without spaces',
		displayOptions: on(R, ['issue']),
	},
	{
		displayName: 'Claims (JSON)',
		name: 'claims',
		type: 'json',
		default: '{}',
		description: 'Named values the statement makes, such as {"age_over_18": true}. Values are text, numbers or true/false.',
		displayOptions: on(R, ['issue']),
	},
	{
		displayName: 'Additional Fields',
		name: 'additionalFields',
		type: 'collection',
		placeholder: 'Add Field',
		default: {},
		displayOptions: on(R, ['issue']),
		options: [
			{ displayName: 'Expires', name: 'expiresAt', type: 'dateTime', default: '' },
			{ displayName: 'Label', name: 'label', type: 'string', default: '' },
			{
				displayName: 'Offer Expires',
				name: 'offerExpiresAt',
				type: 'dateTime',
				default: '',
				description: 'Until when the offer can be accepted. Default: fourteen days.',
			},
			{
				displayName: 'Subject Fingerprint',
				name: 'subjectFingerprint',
				type: 'string',
				default: '',
				description: 'Limits the offer to one identity, such as the one a request was answered with',
			},
		],
	},
	{
		displayName: 'Reason',
		name: 'reason',
		type: 'string',
		default: '',
		displayOptions: on(R, ['revoke']),
	},
	...limitProperties(R),
	statusProperty(R, ['offered', 'active', 'revoked']),
];

export const attestation: Handler = async (ctx, client: Client, operation, i) => {
	switch (operation) {
		case 'issue': {
			const extra = compact(ctx.getNodeParameter('additionalFields', i) as Record<string, unknown>);
			const { attestation: issued, offerToken } = await client.attestations.createWithToken({
				type: ctx.getNodeParameter('type', i) as string,
				claims: jsonParameter<Record<string, unknown>>(ctx, 'claims', i, {}),
				...extra,
			});
			return asData({ ...issued, offerToken, offerLink: client.attestations.offerLink(offerToken) });
		}
		case 'getMany':
			return asList(
				await collect(client.attestations.iterate({ filter: statusFilter(ctx, i), sort: '-created' }), limitOf(ctx, i)),
			);
		case 'get':
			return asData(await client.attestations.get(ctx.getNodeParameter('attestationId', i) as string));
		case 'revoke': {
			const reason = ctx.getNodeParameter('reason', i, '') as string;
			return asData(
				await client.attestations.revoke(ctx.getNodeParameter('attestationId', i) as string, reason || undefined),
			);
		}
	}
	throw new NodeOperationError(ctx.getNode(), `The operation "${operation}" is not supported.`, { itemIndex: i });
};
