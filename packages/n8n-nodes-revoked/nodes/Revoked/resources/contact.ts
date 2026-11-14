import type { INodeProperties } from 'n8n-workflow';
import { NodeOperationError } from 'n8n-workflow';
import { f } from '@kiunke.dev/revoked';
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
} from '../fields';

const R = 'contact';

const contactFields: INodeProperties[] = [
	{ displayName: 'Email', name: 'email', type: 'string', placeholder: 'name@email.com', default: '' },
	{
		displayName: 'Identity Fingerprint',
		name: 'peerFingerprint',
		type: 'string',
		default: '',
		description: 'Fingerprint of the contact’s identity, when known',
	},
	{
		displayName: 'Server Domain',
		name: 'peerDomain',
		type: 'string',
		default: '',
		placeholder: 'example.com',
		description: 'Domain of the Revoked server the contact uses',
	},
];

export const contactProperties: INodeProperties[] = [
	{
		displayName:
			'Sending to a contact or asking a contact for data takes a signed-in person and is not available to API keys',
		name: 'contactNotice',
		type: 'notice',
		default: '',
		displayOptions: { show: { resource: [R] } },
	},
	operationProperty(
		R,
		[
			{ name: 'Create', value: 'create', action: 'Create a contact' },
			{ name: 'Delete', value: 'delete', action: 'Delete a contact' },
			{ name: 'Get', value: 'get', action: 'Get a contact' },
			{ name: 'Get Many', value: 'getMany', action: 'Get many contacts' },
			{ name: 'Update', value: 'update', action: 'Update a contact' },
		],
		'create',
	),
	idProperty(R, 'contactId', 'Contact ID', ['delete', 'get', 'update']),
	{
		displayName: 'Name',
		name: 'name',
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
		options: contactFields,
	},
	{
		displayName: 'Update Fields',
		name: 'updateFields',
		type: 'collection',
		placeholder: 'Add Field',
		default: {},
		displayOptions: on(R, ['update']),
		options: [...contactFields, { displayName: 'Name', name: 'name', type: 'string', default: '' }],
	},
	{
		displayName: 'Search',
		name: 'search',
		type: 'string',
		default: '',
		description: 'Only contacts whose name or email contains this text',
		displayOptions: on(R, ['getMany']),
	},
	...limitProperties(R),
];

export const contact: Handler = async (ctx, client: Client, operation, i) => {
	switch (operation) {
		case 'create': {
			const extra = compact(ctx.getNodeParameter('additionalFields', i) as Record<string, unknown>);
			return asData(await client.contacts.create({ name: ctx.getNodeParameter('name', i) as string, ...extra }));
		}
		case 'getMany': {
			const search = ctx.getNodeParameter('search', i, '') as string;
			const filter = search ? f`name ~ ${search} || email ~ ${search}` : undefined;
			return asList(await collect(client.contacts.iterate({ filter, sort: 'name' }), limitOf(ctx, i)));
		}
	}
	const id = ctx.getNodeParameter('contactId', i) as string;
	switch (operation) {
		case 'get':
			return asData(await client.contacts.get(id));
		case 'update': {
			const fields = compact(ctx.getNodeParameter('updateFields', i) as Record<string, unknown>);
			return asData(await client.contacts.update(id, fields));
		}
		case 'delete':
			await client.contacts.delete(id);
			return asData({ id, deleted: true });
	}
	throw new NodeOperationError(ctx.getNode(), `The operation "${operation}" is not supported.`, { itemIndex: i });
};
