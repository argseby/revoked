import type { INodeProperties } from 'n8n-workflow';
import { NodeOperationError } from 'n8n-workflow';
import {
	asData,
	asList,
	collect,
	type Client,
	type Handler,
	idProperty,
	limitOf,
	limitProperties,
	operationProperty,
	statusFilter,
	statusProperty,
} from '../fields';

const R = 'identity';

export const identityProperties: INodeProperties[] = [
	operationProperty(
		R,
		[
			{ name: 'Get', value: 'get', action: 'Get an identity' },
			{ name: 'Get Many', value: 'getMany', action: 'Get many identities' },
		],
		'getMany',
	),
	idProperty(R, 'identityId', 'Identity ID', ['get']),
	...limitProperties(R),
	statusProperty(R, ['active', 'revoked']),
];

export const identity: Handler = async (ctx, client: Client, operation, i) => {
	switch (operation) {
		case 'get':
			return asData(await client.identities.get(ctx.getNodeParameter('identityId', i) as string));
		case 'getMany':
			return asList(
				await collect(client.identities.iterate({ filter: statusFilter(ctx, i), sort: '-isPrimary,name' }), limitOf(ctx, i)),
			);
	}
	throw new NodeOperationError(ctx.getNode(), `The operation "${operation}" is not supported.`, { itemIndex: i });
};
