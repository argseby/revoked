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
	jsonParameter,
	limitOf,
	limitProperties,
	on,
	operationProperty,
} from '../fields';

const R = 'template';

const SCHEMA_EXAMPLE = JSON.stringify(
	[
		{ key: 'street', label: 'Street', required: true },
		{ key: 'city', label: 'City', required: true },
		{ key: 'phone', label: 'Phone', reason: 'For the courier' },
	],
	null,
	2,
);

type Schema = NonNullable<Parameters<Client['templates']['create']>[0]['schema']>;

/** A list of fields becomes `{ records }`; an object with records or sections is passed on as it is. */
export function toSchema(value: unknown): Schema {
	return (Array.isArray(value) ? { records: value } : value) as Schema;
}

const schemaProperty = (operations: string[], required: boolean, defaultValue: string): INodeProperties => ({
	displayName: 'Fields (JSON)',
	name: 'schema',
	type: 'json',
	required,
	default: defaultValue,
	description:
		'The fields the template asks for, as a list. Each has a key and may have a label, type, format (default or hidden), required and reason. An object with "records" and "sections" is also accepted.',
	displayOptions: on(R, operations),
});

export const templateProperties: INodeProperties[] = [
	operationProperty(
		R,
		[
			{ name: 'Create', value: 'create', action: 'Create a template', description: 'Create a request template' },
			{ name: 'Delete', value: 'delete', action: 'Delete a template' },
			{ name: 'Get', value: 'get', action: 'Get a template' },
			{ name: 'Get Many', value: 'getMany', action: 'Get many templates' },
			{ name: 'Update', value: 'update', action: 'Update a template' },
		],
		'create',
	),
	idProperty(R, 'templateId', 'Template ID', ['delete', 'get', 'update']),
	{
		displayName: 'Name',
		name: 'name',
		type: 'string',
		required: true,
		default: '',
		displayOptions: on(R, ['create']),
	},
	schemaProperty(['create'], true, SCHEMA_EXAMPLE),
	{
		displayName: 'Additional Fields',
		name: 'additionalFields',
		type: 'collection',
		placeholder: 'Add Field',
		default: {},
		displayOptions: on(R, ['create']),
		options: [{ displayName: 'Description', name: 'description', type: 'string', default: '' }],
	},
	{
		displayName: 'Update Fields',
		name: 'updateFields',
		type: 'collection',
		placeholder: 'Add Field',
		default: {},
		displayOptions: on(R, ['update']),
		options: [
			{ displayName: 'Description', name: 'description', type: 'string', default: '' },
			{ displayName: 'Name', name: 'name', type: 'string', default: '' },
		],
	},
	{ ...schemaProperty(['update'], false, ''), description: 'Replaces the template’s fields. Left empty, they stay as they are.' },
	{
		displayName: 'Search',
		name: 'search',
		type: 'string',
		default: '',
		description: 'Only templates whose name contains this text',
		displayOptions: on(R, ['getMany']),
	},
	...limitProperties(R),
];

export const template: Handler = async (ctx, client: Client, operation, i) => {
	switch (operation) {
		case 'create': {
			const extra = compact(ctx.getNodeParameter('additionalFields', i) as Record<string, unknown>);
			return asData(
				await client.templates.create({
					name: ctx.getNodeParameter('name', i) as string,
					schema: toSchema(jsonParameter<unknown>(ctx, 'schema', i, [])),
					...extra,
				}),
			);
		}
		case 'getMany': {
			const search = ctx.getNodeParameter('search', i, '') as string;
			const filter = search ? f`name ~ ${search}` : undefined;
			return asList(await collect(client.templates.iterate({ filter, sort: 'name' }), limitOf(ctx, i)));
		}
	}
	const id = ctx.getNodeParameter('templateId', i) as string;
	switch (operation) {
		case 'get':
			return asData(await client.templates.get(id));
		case 'update': {
			const fields = compact(ctx.getNodeParameter('updateFields', i) as Record<string, unknown>);
			const schema = jsonParameter<unknown>(ctx, 'schema', i, undefined);
			return asData(await client.templates.update(id, { ...fields, ...(schema ? { schema: toSchema(schema) } : {}) }));
		}
		case 'delete':
			await client.templates.delete(id);
			return asData({ id, deleted: true });
	}
	throw new NodeOperationError(ctx.getNode(), `The operation "${operation}" is not supported.`, { itemIndex: i });
};
