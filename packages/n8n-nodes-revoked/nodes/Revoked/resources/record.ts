import type { IExecuteFunctions, INodeProperties } from 'n8n-workflow';
import { NodeOperationError } from 'n8n-workflow';
import { compact } from '../shared';
import {
	asData,
	asList,
	type Client,
	type Handler,
	Items,
	limitOf,
	limitProperties,
	on,
	operationProperty,
} from '../fields';

const R = 'record';

const formatProperty: INodeProperties = {
	displayName: 'Format',
	name: 'format',
	type: 'options',
	options: [
		{ name: 'Default', value: 'default' },
		{ name: 'Hidden', value: 'hidden' },
	],
	default: 'default',
	description: 'Hidden suits secrets',
};

const binaryProperty: INodeProperties = {
	displayName: 'Input Binary Field',
	name: 'binaryPropertyName',
	type: 'string',
	default: '',
	placeholder: 'data',
	description: 'Name of a binary field on the input item. When set, the record holds that file instead of a value.',
};

export const recordProperties: INodeProperties[] = [
	operationProperty(
		R,
		[
			{ name: 'Create', value: 'create', action: 'Create a vault record' },
			{
				name: 'Delete',
				value: 'delete',
				action: 'Delete a vault record',
				description: 'Only records written by this key can be deleted',
			},
			{
				name: 'Download File',
				value: 'download',
				action: 'Download the file of a vault record',
				description: 'The file of a file record, as binary data',
			},
			{
				name: 'Get',
				value: 'get',
				action: 'Get a vault record',
				description: 'Get a record with its value. Each read is in the owner’s audit log.',
			},
			{ name: 'Get by Key', value: 'getByKey', action: 'Get a vault record by key' },
			{
				name: 'Get Many',
				value: 'getMany',
				action: 'Get many vault records',
				description: 'Records within the key’s sections, without values',
			},
			{
				name: 'Update',
				value: 'update',
				action: 'Update a vault record',
				description: 'Only records written by this key can be updated',
			},
		],
		'getByKey',
	),
	{
		displayName: 'Record Name or ID',
		name: 'recordId',
		type: 'options',
		typeOptions: { loadOptionsMethod: 'getRecords' },
		required: true,
		default: '',
		description:
					'Choose from the list, or specify an ID using an <a href="https://docs.n8n.io/code/expressions/">expression</a>',
		displayOptions: on(R, ['delete', 'download', 'get', 'update']),
	},
	{
		displayName: 'Key',
		name: 'key',
		type: 'string',
		required: true,
		default: '',
		placeholder: 'wifi_password',
		displayOptions: on(R, ['create', 'getByKey']),
	},
	{
		displayName: 'Value',
		name: 'value',
		type: 'string',
		typeOptions: { password: true },
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
			formatProperty,
			binaryProperty,
			{ displayName: 'Label', name: 'label', type: 'string', default: '' },
			{
				displayName: 'Section ID',
				name: 'section',
				type: 'string',
				default: '',
				description: 'One of the key’s sections. Default: the first of them.',
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
		options: [
			formatProperty,
			binaryProperty,
			{ displayName: 'Label', name: 'label', type: 'string', default: '' },
			{ displayName: 'Value', name: 'value', type: 'string', typeOptions: { password: true }, default: '' },
		],
	},
	{
		displayName: 'Put Output File in Field',
		name: 'binaryOutput',
		type: 'string',
		default: 'data',
		displayOptions: on(R, ['download']),
	},
	...limitProperties(R),
];

async function withFile(ctx: IExecuteFunctions, fields: Record<string, unknown>, i: number) {
	const { binaryPropertyName, ...rest } = fields;
	if (typeof binaryPropertyName !== 'string' || binaryPropertyName === '') return rest;
	const meta = ctx.helpers.assertBinaryData(i, binaryPropertyName);
	const bytes = await ctx.helpers.getBinaryDataBuffer(i, binaryPropertyName);
	return {
		...rest,
		type: 'file',
		filename: meta.fileName ?? 'file',
		file: new Blob([new Uint8Array(bytes)], { type: meta.mimeType }),
	};
}

export const record: Handler = async (ctx, client: Client, operation, i) => {
	switch (operation) {
		case 'create': {
			const extra = await withFile(ctx, compact(ctx.getNodeParameter('additionalFields', i) as Record<string, unknown>), i);
			const value = ctx.getNodeParameter('value', i, '') as string;
			return asData(
				await client.vault.create({
					key: ctx.getNodeParameter('key', i) as string,
					...(value === '' ? {} : { value }),
					...extra,
				}),
			);
		}
		case 'get':
			return asData(await client.vault.get(ctx.getNodeParameter('recordId', i) as string));
		case 'getByKey': {
			const key = ctx.getNodeParameter('key', i) as string;
			const found = await client.vault.find(key);
			if (!found) {
				throw new NodeOperationError(ctx.getNode(), `No record with the key "${key}" is within reach.`, { itemIndex: i });
			}
			return asData(found);
		}
		case 'getMany': {
			const all = await client.vault.list();
			const limit = limitOf(ctx, i);
			return asList(limit === undefined ? all : all.slice(0, limit));
		}
		case 'update': {
			const fields = await withFile(ctx, compact(ctx.getNodeParameter('updateFields', i) as Record<string, unknown>), i);
			delete (fields as Record<string, unknown>).type;
			return asData(await client.vault.update(ctx.getNodeParameter('recordId', i) as string, fields));
		}
		case 'delete': {
			const id = ctx.getNodeParameter('recordId', i) as string;
			await client.vault.delete(id);
			return asData({ id, deleted: true });
		}
		case 'download': {
			const id = ctx.getNodeParameter('recordId', i) as string;
			const field = ctx.getNodeParameter('binaryOutput', i) as string;
			const file = await client.vault.file(id);
			const binary = await ctx.helpers.prepareBinaryData(
				Buffer.from(await file.blob.arrayBuffer()),
				file.filename,
				file.contentType,
			);
			return new Items([{ json: { id, filename: file.filename ?? null }, binary: { [field]: binary }, pairedItem: { item: i } }]);
		}
	}
	throw new NodeOperationError(ctx.getNode(), `The operation "${operation}" is not supported.`, { itemIndex: i });
};
