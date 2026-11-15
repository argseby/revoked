import type { INodeProperties } from 'n8n-workflow';
import { NodeOperationError } from 'n8n-workflow';
import type { Link } from '@kiunke.dev/revoked';
import { compact, ids } from '../shared';
import {
	asData,
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

const R = 'share';

const shareOptions: INodeProperties[] = [
	{ displayName: 'Expires', name: 'expiresAt', type: 'dateTime', default: '' },
	{
		displayName: 'Maximum Views',
		name: 'maxViews',
		type: 'number',
		typeOptions: { minValue: 0 },
		default: 0,
		description: '0 means no limit',
	},
];

export const shareProperties: INodeProperties[] = [
	operationProperty(
		R,
		[
			{ name: 'Create', value: 'create', action: 'Create a share', description: 'Create a share over vault records' },
			{ name: 'Delete', value: 'delete', action: 'Delete a share', description: 'Delete a share and its history' },
			{ name: 'Get', value: 'get', action: 'Get a share' },
			{ name: 'Get Many', value: 'getMany', action: 'Get many shares' },
			{ name: 'Pause', value: 'pause', action: 'Pause a share', description: 'Refuse readers until resumed' },
			{ name: 'Resume', value: 'resume', action: 'Resume a share' },
			{ name: 'Revoke', value: 'revoke', action: 'Revoke a share', description: 'End a share. This cannot be undone.' },
			{ name: 'Update', value: 'update', action: 'Update a share' },
		],
		'create',
	),
	idProperty(R, 'shareId', 'Share ID', ['delete', 'get', 'pause', 'resume', 'revoke', 'update']),
	{
		displayName: 'Label',
		name: 'label',
		type: 'string',
		required: true,
		default: '',
		displayOptions: on(R, ['create']),
	},
	{
		displayName: 'Record Names or IDs',
		name: 'records',
		type: 'multiOptions',
		typeOptions: { loadOptionsMethod: 'getRecords' },
		required: true,
		default: [],
		description:
			'Records within the key’s sections. Choose from the list, or specify IDs using an <a href="https://docs.n8n.io/code/expressions/">expression</a>.',
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
			...shareOptions,
			{
				displayName: 'Password',
				name: 'password',
				type: 'string',
				typeOptions: { password: true },
				default: '',
				description: 'Stored hashed and never returned',
			},
			{
				displayName: 'Require a Verified Viewer',
				name: 'requireHandshake',
				type: 'boolean',
				default: false,
				description: 'Whether readers must prove an identity before the share opens',
			},
			{
				displayName: 'Watermark',
				name: 'watermark',
				type: 'boolean',
				default: false,
				description: 'Whether files are served with a watermark',
			},
			{
				displayName: 'Watermark Text',
				name: 'watermarkText',
				type: 'string',
				default: '',
				description: 'One line of 1 to 120 characters',
			},
		],
	},
	{
		displayName: 'Update Fields',
		name: 'updateFields',
		type: 'collection',
		placeholder: 'Add Field',
		default: {},
		displayOptions: on(R, ['update']),
		options: [...shareOptions, { displayName: 'Label', name: 'label', type: 'string', default: '' }],
	},
	...limitProperties(R),
	statusProperty(R, ['active', 'paused', 'revoked', 'expired']),
];

export const share: Handler = async (ctx, client: Client, operation, i) => {
	const withUrls = (link: Link) => ({ ...link, url: client.links.url(link), appLink: client.links.appLink(link) });

	if (operation === 'create') {
		const extra = compact(ctx.getNodeParameter('additionalFields', i) as Record<string, unknown>);
		const link = await client.links.create({
			label: ctx.getNodeParameter('label', i) as string,
			records: ids(ctx.getNodeParameter('records', i)),
			...extra,
		});
		return withUrls(link);
	}
	if (operation === 'getMany') {
		const links = await collect(client.links.iterate({ filter: statusFilter(ctx, i), sort: '-created' }), limitOf(ctx, i));
		return links.map(withUrls);
	}
	const id = ctx.getNodeParameter('shareId', i) as string;
	switch (operation) {
		case 'get':
			return withUrls(await client.links.get(id));
		case 'pause':
			return withUrls(await client.links.pause(id));
		case 'resume':
			return withUrls(await client.links.resume(id));
		case 'revoke':
			return withUrls(await client.links.revoke(id));
		case 'update': {
			const fields = compact(ctx.getNodeParameter('updateFields', i) as Record<string, unknown>);
			return withUrls(await client.links.update(id, fields));
		}
		case 'delete':
			await client.links.delete(id);
			return asData({ id, deleted: true });
	}
	throw new NodeOperationError(ctx.getNode(), `The operation "${operation}" is not supported.`, { itemIndex: i });
};
