import { f } from '@kiunke.dev/revoked';
import type {
	IExecuteFunctions,
	ILoadOptionsFunctions,
	INodeExecutionData,
	INodeProperties,
	INodePropertyOptions,
	INodeType,
	INodeTypeDescription,
} from 'n8n-workflow';
import { NodeConnectionTypes, NodeOperationError } from 'n8n-workflow';
import { collect, type Handler, Items } from './fields';
import { attestation, attestationProperties } from './resources/attestation';
import { contact, contactProperties } from './resources/contact';
import { identity, identityProperties } from './resources/identity';
import { record, recordProperties } from './resources/record';
import { request, requestProperties } from './resources/request';
import { share, shareProperties } from './resources/share';
import { template, templateProperties } from './resources/template';
import { webhookDelivery, webhookEndpoint, webhookEvent, webhookProperties } from './resources/webhook';
import { nodeError, revokedClient } from './shared';

const handlers: Record<string, Handler> = {
	attestation,
	contact,
	identity,
	record,
	request,
	share,
	template,
	webhookDelivery,
	webhookEndpoint,
	webhookEvent,
};

const resourceProperty: INodeProperties = {
	displayName: 'Resource',
	name: 'resource',
	type: 'options',
	noDataExpression: true,
	options: [
		{ name: 'Attestation', value: 'attestation' },
		{ name: 'Contact', value: 'contact' },
		{ name: 'Identity', value: 'identity' },
		{ name: 'Request', value: 'request' },
		{ name: 'Share', value: 'share' },
		{ name: 'Template', value: 'template' },
		{ name: 'Vault Record', value: 'record' },
		{ name: 'Webhook Delivery', value: 'webhookDelivery' },
		{ name: 'Webhook Endpoint', value: 'webhookEndpoint' },
		{ name: 'Webhook Event', value: 'webhookEvent' },
	],
	default: 'share',
};

export class Revoked implements INodeType {
	description: INodeTypeDescription = {
		displayName: 'Revoked',
		name: 'revoked',
		icon: { light: 'file:revoked.svg', dark: 'file:revoked.dark.svg' },
		group: ['transform'],
		version: 1,
		subtitle: '={{$parameter["operation"] + ": " + $parameter["resource"]}}',
		description: 'Shares, requests, vault records, contacts, attestations and webhooks on a Revoked server',
		defaults: { name: 'Revoked' },
		usableAsTool: true,
		inputs: [NodeConnectionTypes.Main],
		outputs: [NodeConnectionTypes.Main],
		credentials: [{ name: 'revokedApi', required: true }],
		properties: [
			resourceProperty,
			...shareProperties,
			...requestProperties,
			...recordProperties,
			...templateProperties,
			...contactProperties,
			...attestationProperties,
			...identityProperties,
			...webhookProperties,
		],
	};

	methods = {
		loadOptions: {
			async getRecords(this: ILoadOptionsFunctions): Promise<INodePropertyOptions[]> {
				const client = await revokedClient(this);
				const entries = await client.vault.list();
				return entries.map((e) => ({ name: e.label ? `${e.label} (${e.key})` : e.key, value: e.id }));
			},
			async getIdentities(this: ILoadOptionsFunctions): Promise<INodePropertyOptions[]> {
				const client = await revokedClient(this);
				const identities = await collect(
					client.identities.iterate({ filter: f`status = ${'active'}`, sort: '-isPrimary,name' }),
					500,
				);
				return identities.map((i) => ({
					name: i.isPrimary ? `${i.name} (primary)` : i.name,
					value: i.id,
					description: i.fingerprint,
				}));
			},
			async getTemplates(this: ILoadOptionsFunctions): Promise<INodePropertyOptions[]> {
				const client = await revokedClient(this);
				const templates = await collect(client.templates.iterate({ sort: 'name' }), 500);
				return templates.map((t) => ({ name: t.name, value: t.id, description: t.description }));
			},
		},
	};

	async execute(this: IExecuteFunctions): Promise<INodeExecutionData[][]> {
		const items = this.getInputData();
		const client = await revokedClient(this);
		const out: INodeExecutionData[] = [];

		for (let i = 0; i < items.length; i++) {
			try {
				const resource = this.getNodeParameter('resource', i) as string;
				const operation = this.getNodeParameter('operation', i) as string;
				const handler = handlers[resource];
				if (!handler) {
					throw new NodeOperationError(this.getNode(), `The resource "${resource}" is not supported.`, { itemIndex: i });
				}
				const result = await handler(this, client, operation, i);
				if (result instanceof Items) out.push(...result.items);
				else out.push(...this.helpers.constructExecutionMetaData(this.helpers.returnJsonArray(result), { itemData: { item: i } }));
			} catch (error) {
				if (this.continueOnFail()) {
					out.push({ json: { error: (error as Error).message }, pairedItem: { item: i } });
					continue;
				}
				throw nodeError(this.getNode(), error, i);
			}
		}
		return [out];
	}
}
