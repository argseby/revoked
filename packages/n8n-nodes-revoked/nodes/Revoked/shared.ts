import { Revoked, RevokedError } from '@kiunke.dev/revoked';
import type {
	IExecuteFunctions,
	IHookFunctions,
	ILoadOptionsFunctions,
	INode,
	IWebhookFunctions,
} from 'n8n-workflow';
import { NodeOperationError } from 'n8n-workflow';

export interface RevokedCredentials {
	server: string;
	apiKey: string;
}

type Context = IExecuteFunctions | IHookFunctions | ILoadOptionsFunctions | IWebhookFunctions;

export async function revokedClient(ctx: Context): Promise<Revoked> {
	const credentials = await ctx.getCredentials<RevokedCredentials>('revokedApi');
	return new Revoked({ server: credentials.server, apiKey: credentials.apiKey });
}

export function nodeError(node: INode, error: unknown, itemIndex?: number): NodeOperationError {
	if (error instanceof NodeOperationError) return error;
	const options = itemIndex === undefined ? {} : { itemIndex };
	if (error instanceof RevokedError && error.code === 'identity_required') {
		return new NodeOperationError(node, 'No identity was found for the request.', {
			...options,
			description:
				'Requests are made in the name of an identity. One can be chosen under Additional Fields → Identity; otherwise the workspace’s primary identity is used. Listing identities needs the View identities permission on the key.',
		});
	}
	if (error instanceof RevokedError) {
		const fields = Object.entries(error.fields).map(([name, field]) => `${name}: ${field.message}`);
		const description = [`Code: ${error.code}`, ...fields].join('\n');
		return new NodeOperationError(node, error.message, { ...options, description });
	}
	return new NodeOperationError(node, error as Error, options);
}

export function isNotFound(error: unknown): boolean {
	return error instanceof RevokedError && error.status === 404;
}

/** Drops fields left empty in the editor, so they keep the server's default instead of being sent as "". */
export function compact<T extends Record<string, unknown>>(fields: T): Partial<T> {
	return Object.fromEntries(
		Object.entries(fields).filter(([, v]) => v !== '' && v !== undefined && v !== null),
	) as Partial<T>;
}

/** Accepts a list from a multi-select or a comma-separated string from an expression. */
export function ids(value: unknown): string[] {
	if (Array.isArray(value)) return value.map(String).filter((v) => v !== '');
	if (typeof value === 'string') {
		return value
			.split(',')
			.map((v) => v.trim())
			.filter((v) => v !== '');
	}
	return [];
}
