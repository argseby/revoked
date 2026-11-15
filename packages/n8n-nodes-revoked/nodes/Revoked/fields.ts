import type { IDataObject, IExecuteFunctions, INodeExecutionData, INodeProperties } from 'n8n-workflow';
import type { Revoked } from '@kiunke.dev/revoked';
import { f } from '@kiunke.dev/revoked';

/** Finished output items, for results that carry binary data. */
export class Items {
	constructor(readonly items: INodeExecutionData[]) {}
}

export type Client = Revoked;
export type Result = IDataObject | IDataObject[] | Items;
export type Handler = (ctx: IExecuteFunctions, client: Client, operation: string, i: number) => Promise<Result>;

export const on = (resource: string, operation: string[]) => ({ show: { resource: [resource], operation } });

export function operationProperty(
	resource: string,
	options: Array<{ name: string; value: string; action: string; description?: string }>,
	defaultValue: string,
): INodeProperties {
	return {
		displayName: 'Operation',
		name: 'operation',
		type: 'options',
		noDataExpression: true,
		displayOptions: { show: { resource: [resource] } },
		options,
		default: defaultValue,
	};
}

export function idProperty(resource: string, name: string, displayName: string, operations: string[]): INodeProperties {
	return {
		displayName,
		name,
		type: 'string',
		required: true,
		default: '',
		displayOptions: on(resource, operations),
	};
}

export function limitProperties(resource: string, operations = ['getMany']): INodeProperties[] {
	return [
		{
			displayName: 'Return All',
			name: 'returnAll',
			type: 'boolean',
			default: false,
			description: 'Whether to return all results or only up to a given limit',
			displayOptions: on(resource, operations),
		},
		{
			displayName: 'Limit',
			name: 'limit',
			type: 'number',
			typeOptions: { minValue: 1 },
			default: 50,
			description: 'Max number of results to return',
			displayOptions: { show: { resource: [resource], operation: operations, returnAll: [false] } },
		},
	];
}

export function statusProperty(resource: string, statuses: string[]): INodeProperties {
	return {
		displayName: 'Status',
		name: 'status',
		type: 'options',
		default: '',
		options: [
			{ name: 'Any', value: '' },
			...statuses.map((s) => ({ name: s.charAt(0).toUpperCase() + s.slice(1), value: s })),
		],
		displayOptions: on(resource, ['getMany']),
	};
}

export async function collect<T>(source: AsyncIterable<T>, limit: number | undefined): Promise<T[]> {
	const out: T[] = [];
	for await (const item of source) {
		out.push(item);
		if (limit !== undefined && out.length >= limit) break;
	}
	return out;
}

export function limitOf(ctx: IExecuteFunctions, i: number): number | undefined {
	return ctx.getNodeParameter('returnAll', i) ? undefined : (ctx.getNodeParameter('limit', i) as number);
}

export function statusFilter(ctx: IExecuteFunctions, i: number) {
	const status = ctx.getNodeParameter('status', i, '') as string;
	return status ? f`status = ${status}` : undefined;
}

/** Accepts a JSON field as an object or as the JSON text an expression produced. */
export function jsonParameter<T>(ctx: IExecuteFunctions, name: string, i: number, fallback: T): T {
	const value = ctx.getNodeParameter(name, i, fallback) as unknown;
	if (typeof value === 'string') return value.trim() === '' ? fallback : (JSON.parse(value) as T);
	return (value ?? fallback) as T;
}

export const asData = (value: unknown) => value as IDataObject;
export const asList = (value: unknown) => value as IDataObject[];
