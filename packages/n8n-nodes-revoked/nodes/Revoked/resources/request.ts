import type { INodeProperties } from 'n8n-workflow';
import { NodeOperationError } from 'n8n-workflow';
import type { RevokedRequest } from '@kiunke.dev/revoked';
import { compact } from '../shared';
import {
	asData,
	asList,
	collect,
	type Client,
	type Handler,
	idProperty,
	limitOf,
	limitProperties,
	on,
	operationProperty,
	statusFilter,
	statusProperty,
} from '../fields';

const R = 'request';

export const requestProperties: INodeProperties[] = [
	operationProperty(
		R,
		[
			{ name: 'Close', value: 'close', action: 'Close a request', description: 'Stop new answers. Given answers stay with their responders.' },
			{ name: 'Create', value: 'create', action: 'Create a request', description: 'Create a request for data' },
			{ name: 'Delete', value: 'delete', action: 'Delete a request' },
			{ name: 'Get', value: 'get', action: 'Get a request' },
			{
				name: 'Get Answers',
				value: 'getAnswers',
				action: 'Get the answers to a request',
				description: 'One item per answer, with its current values',
			},
			{ name: 'Get Many', value: 'getMany', action: 'Get many requests' },
			{ name: 'Pause', value: 'pause', action: 'Pause a request' },
			{ name: 'Resume', value: 'resume', action: 'Resume a request' },
		],
		'create',
	),
	idProperty(R, 'requestId', 'Request ID', ['close', 'delete', 'get', 'getAnswers', 'pause', 'resume']),
	{
		displayName: 'Label',
		name: 'label',
		type: 'string',
		required: true,
		default: '',
		displayOptions: on(R, ['create']),
	},
	{
		displayName: 'Additional Fields',
		name: 'additionalFields',
		type: 'collection',
		placeholder: 'Add Field',
		default: {},
		displayOptions: on(R, ['create']),
		options: [
			{
				displayName: 'Allow Extra Fields',
				name: 'allowExtraFields',
				type: 'boolean',
				default: false,
				description: 'Whether responders may add fields the template does not ask for',
			},
			{ displayName: 'Expires', name: 'expiresAt', type: 'dateTime', default: '' },
			{
				displayName: 'Identifier',
				name: 'identifier',
				type: 'string',
				default: '',
				placeholder: 'Order number',
				description: 'Label of a value each responder must give, such as an order number',
			},
			{
				displayName: 'Identity Name or ID',
				name: 'identity',
				type: 'options',
				typeOptions: { loadOptionsMethod: 'getIdentities' },
				default: '',
				description:
					'The identity the request is made in the name of. Default: the workspace’s primary identity. Choose from the list, or specify an ID using an <a href="https://docs.n8n.io/code/expressions/">expression</a>.',
			},
			{
				displayName: 'Max Responses',
				name: 'maxResponses',
				type: 'number',
				typeOptions: { minValue: 0 },
				default: 0,
				description: '0 means no limit',
			},
			{
				displayName: 'Password',
				name: 'password',
				type: 'string',
				typeOptions: { password: true },
				default: '',
				description: 'Stored hashed and never returned',
			},
			{
				displayName: 'Require a Verified Identity',
				name: 'requireHandshake',
				type: 'boolean',
				default: false,
				description: 'Whether responders must prove an identity before answering',
			},
			{
				displayName: 'Template Name or ID',
				name: 'template',
				type: 'options',
				typeOptions: { loadOptionsMethod: 'getTemplates' },
				default: '',
				description:
					'Choose from the list, or specify an ID using an <a href="https://docs.n8n.io/code/expressions/">expression</a>',
			},
		],
	},
	...limitProperties(R),
	statusProperty(R, ['active', 'paused', 'revoked', 'expired', 'completed']),
];

export const request: Handler = async (ctx, client: Client, operation, i) => {
	const withLink = (r: RevokedRequest) => ({ ...r, appLink: client.requests.appLink(r) });

	if (operation === 'create') {
		const extra = compact(ctx.getNodeParameter('additionalFields', i) as Record<string, unknown>);
		return withLink(await client.requests.create({ label: ctx.getNodeParameter('label', i) as string, ...extra }));
	}
	if (operation === 'getMany') {
		const list = await collect(client.requests.iterate({ filter: statusFilter(ctx, i), sort: '-created' }), limitOf(ctx, i));
		return list.map(withLink);
	}
	const id = ctx.getNodeParameter('requestId', i) as string;
	switch (operation) {
		case 'get':
			return withLink(await client.requests.get(id));
		case 'getAnswers':
			return asList(await client.requests.responses(id));
		case 'pause':
			return withLink(await client.requests.pause(id));
		case 'resume':
			return withLink(await client.requests.resume(id));
		case 'close':
			return withLink(await client.requests.close(id));
		case 'delete':
			await client.requests.delete(id);
			return asData({ id, deleted: true });
	}
	throw new NodeOperationError(ctx.getNode(), `The operation "${operation}" is not supported.`, { itemIndex: i });
};
