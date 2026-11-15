import type { INodeProperties } from 'n8n-workflow';
import { NodeOperationError } from 'n8n-workflow';
import { WEBHOOK_EVENT_TYPES } from '@kiunke.dev/revoked/webhooks';
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

const ENDPOINT = 'webhookEndpoint';
const DELIVERY = 'webhookDelivery';
const EVENT = 'webhookEvent';

export const eventTypeOptions = WEBHOOK_EVENT_TYPES.map((e) => ({
	name: e.type,
	value: e.type,
	description: e.noisy ? `${e.group}. Sent often.` : e.group,
}));

const eventsProperty = (operations: string[], required: boolean): INodeProperties => ({
	displayName: 'Events',
	name: 'events',
	type: 'multiOptions',
	required,
	default: [],
	options: eventTypeOptions,
	description: 'Left empty, every event except the frequent ones is sent',
	displayOptions: on(ENDPOINT, operations),
});

export const webhookProperties: INodeProperties[] = [
	operationProperty(
		ENDPOINT,
		[
			{
				name: 'Create',
				value: 'create',
				action: 'Create a webhook endpoint',
				description: 'The answer carries the signing secret, shown once',
			},
			{ name: 'Delete', value: 'delete', action: 'Delete a webhook endpoint' },
			{ name: 'Get', value: 'get', action: 'Get a webhook endpoint' },
			{ name: 'Get Many', value: 'getMany', action: 'Get many webhook endpoints' },
			{
				name: 'Rotate Secret',
				value: 'rotateSecret',
				action: 'Rotate the secret of a webhook endpoint',
				description: 'The old secret keeps signing alongside the new one for 24 hours',
			},
			{
				name: 'Send Test Event',
				value: 'test',
				action: 'Send a test event to a webhook endpoint',
			},
			{ name: 'Update', value: 'update', action: 'Update a webhook endpoint' },
		],
		'getMany',
	),
	idProperty(ENDPOINT, 'endpointId', 'Endpoint ID', ['delete', 'get', 'rotateSecret', 'test', 'update']),
	{
		displayName: 'URL',
		name: 'url',
		type: 'string',
		required: true,
		default: '',
		placeholder: 'https://example.com/hooks/revoked',
		displayOptions: on(ENDPOINT, ['create']),
	},
	eventsProperty(['create'], false),
	{
		displayName: 'Additional Fields',
		name: 'additionalFields',
		type: 'collection',
		placeholder: 'Add Field',
		default: {},
		displayOptions: on(ENDPOINT, ['create']),
		options: [{ displayName: 'Description', name: 'description', type: 'string', default: '' }],
	},
	{
		displayName: 'Update Fields',
		name: 'updateFields',
		type: 'collection',
		placeholder: 'Add Field',
		default: {},
		displayOptions: on(ENDPOINT, ['update']),
		options: [
			{ displayName: 'Description', name: 'description', type: 'string', default: '' },
			{
				displayName: 'Enabled',
				name: 'enabled',
				type: 'boolean',
				default: true,
				description: 'Whether events are sent to the endpoint',
			},
			{ displayName: 'Events', name: 'events', type: 'multiOptions', default: [], options: eventTypeOptions },
			{ displayName: 'URL', name: 'url', type: 'string', default: '' },
		],
	},
	{
		displayName: 'Event Type',
		name: 'eventType',
		type: 'options',
		required: true,
		default: 'response.submitted',
		options: eventTypeOptions,
		displayOptions: on(ENDPOINT, ['test']),
	},

	operationProperty(
		DELIVERY,
		[
			{ name: 'Get', value: 'get', action: 'Get a webhook delivery', description: 'Get a delivery with its attempts' },
			{ name: 'Get Many', value: 'getMany', action: 'Get many webhook deliveries' },
			{ name: 'Resend', value: 'resend', action: 'Resend a webhook delivery' },
		],
		'getMany',
	),
	{
		displayName: 'Delivery ID',
		name: 'deliveryId',
		type: 'string',
		required: true,
		default: '',
		displayOptions: on(DELIVERY, ['get', 'resend']),
	},
	{
		displayName: 'Filters',
		name: 'filters',
		type: 'collection',
		placeholder: 'Add Filter',
		default: {},
		displayOptions: on(DELIVERY, ['getMany']),
		options: [
			{ displayName: 'Endpoint ID', name: 'endpoint', type: 'string', default: '' },
			{ displayName: 'Event Type', name: 'type', type: 'options', default: 'response.submitted', options: eventTypeOptions },
			{
				displayName: 'Status',
				name: 'status',
				type: 'options',
				default: 'failed',
				options: [
					{ name: 'Failed', value: 'failed' },
					{ name: 'Pending', value: 'pending' },
					{ name: 'Succeeded', value: 'succeeded' },
				],
			},
		],
	},
	...limitProperties(DELIVERY),

	operationProperty(
		EVENT,
		[{ name: 'Get Many', value: 'getMany', action: 'Get many webhook events', description: 'Events recorded in the workspace' }],
		'getMany',
	),
	{
		displayName: 'Event Type',
		name: 'eventType',
		type: 'options',
		default: '',
		options: [{ name: 'Any', value: '' }, ...eventTypeOptions],
		displayOptions: on(EVENT, ['getMany']),
	},
	...limitProperties(EVENT),
];

export const webhookEndpoint: Handler = async (ctx, client: Client, operation, i) => {
	const endpoints = client.webhooks.endpoints;
	switch (operation) {
		case 'create': {
			const extra = compact(ctx.getNodeParameter('additionalFields', i) as Record<string, unknown>);
			const events = ctx.getNodeParameter('events', i, []) as string[];
			return asData(
				await endpoints.create({
					url: ctx.getNodeParameter('url', i) as string,
					events: events.length ? events : ['*'],
					...extra,
				}),
			);
		}
		case 'getMany': {
			const all = await endpoints.list();
			const limit = limitOf(ctx, i);
			return asList(limit === undefined ? all : all.slice(0, limit));
		}
	}
	const id = ctx.getNodeParameter('endpointId', i) as string;
	switch (operation) {
		case 'get':
			return asData(await endpoints.get(id));
		case 'update': {
			const fields = compact(ctx.getNodeParameter('updateFields', i) as Record<string, unknown>);
			return asData(await endpoints.update(id, fields));
		}
		case 'delete':
			await endpoints.delete(id);
			return asData({ id, deleted: true });
		case 'rotateSecret':
			return asData({ id, secret: await endpoints.rotateSecret(id) });
		case 'test':
			return asData(await endpoints.test(id, ctx.getNodeParameter('eventType', i) as string));
	}
	throw new NodeOperationError(ctx.getNode(), `The operation "${operation}" is not supported.`, { itemIndex: i });
};

export const webhookDelivery: Handler = async (ctx, client: Client, operation, i) => {
	const deliveries = client.webhooks.deliveries;
	switch (operation) {
		case 'getMany': {
			const filters = compact(ctx.getNodeParameter('filters', i, {}) as Record<string, unknown>);
			return asList(await collect(deliveries.iterate(filters), limitOf(ctx, i)));
		}
		case 'get':
			return asData(await deliveries.get(ctx.getNodeParameter('deliveryId', i) as string));
		case 'resend':
			return asData(await deliveries.resend(ctx.getNodeParameter('deliveryId', i) as string));
	}
	throw new NodeOperationError(ctx.getNode(), `The operation "${operation}" is not supported.`, { itemIndex: i });
};

export const webhookEvent: Handler = async (ctx, client: Client, operation, i) => {
	if (operation === 'getMany') {
		const type = ctx.getNodeParameter('eventType', i, '') as string;
		return asList(await collect(client.webhooks.events.iterate(type ? { type } : {}), limitOf(ctx, i)));
	}
	throw new NodeOperationError(ctx.getNode(), `The operation "${operation}" is not supported.`, { itemIndex: i });
};
