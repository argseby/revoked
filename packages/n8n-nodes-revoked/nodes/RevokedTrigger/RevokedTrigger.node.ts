import { WEBHOOK_SIGNATURE_HEADER, verifyWebhook } from '@kiunke.dev/revoked/webhooks';
import type {
	IDataObject,
	IHookFunctions,
	INodeType,
	INodeTypeDescription,
	IWebhookFunctions,
	IWebhookResponseData,
} from 'n8n-workflow';
import { NodeConnectionTypes } from 'n8n-workflow';
import { eventTypeOptions } from '../Revoked/resources/webhook';
import { isNotFound, nodeError, revokedClient } from '../Revoked/shared';

interface EndpointState {
	endpointId?: string;
	endpointSecret?: string;
}

function sameEvents(a: readonly string[], b: readonly string[]): boolean {
	return a.length === b.length && [...a].sort().join(',') === [...b].sort().join(',');
}

export class RevokedTrigger implements INodeType {
	description: INodeTypeDescription = {
		displayName: 'Revoked Trigger',
		name: 'revokedTrigger',
		icon: { light: 'file:../Revoked/revoked.svg', dark: 'file:../Revoked/revoked.dark.svg' },
		group: ['trigger'],
		version: 1,
		subtitle: '={{$parameter["events"].join(", ")}}',
		description: 'Starts the workflow on Revoked webhook events',
		defaults: { name: 'Revoked Trigger' },
		inputs: [],
		outputs: [NodeConnectionTypes.Main],
		credentials: [{ name: 'revokedApi', required: true }],
		webhooks: [{ name: 'default', httpMethod: 'POST', responseMode: 'onReceived', path: 'webhook' }],
		properties: [
			{
				displayName:
					'The key needs the Manage webhooks permission, and the server must be able to reach this n8n instance. Private addresses are refused unless the server allows them.',
				name: 'notice',
				type: 'notice',
				default: '',
			},
			{
				displayName: 'Events',
				name: 'events',
				type: 'multiOptions',
				required: true,
				default: ['response.submitted'],
				options: eventTypeOptions,
			},
			{
				displayName: 'Options',
				name: 'options',
				type: 'collection',
				placeholder: 'Add Option',
				default: {},
				options: [
					{
						displayName: 'Include Answer',
						name: 'includeAnswer',
						type: 'boolean',
						default: false,
						description:
							'Whether response events carry the answer with its current values. Needs the View requests permission.',
					},
				],
			},
		],
	};

	webhookMethods = {
		default: {
			async checkExists(this: IHookFunctions): Promise<boolean> {
				const state = this.getWorkflowStaticData('node') as EndpointState;
				if (!state.endpointId || !state.endpointSecret) return false;
				const client = await revokedClient(this);
				try {
					const endpoint = await client.webhooks.endpoints.get(state.endpointId);
					const events = this.getNodeParameter('events') as string[];
					if (endpoint.url === this.getNodeWebhookUrl('default') && sameEvents(endpoint.events, events)) {
						return true;
					}
					await client.webhooks.endpoints.delete(state.endpointId);
				} catch (error) {
					if (!isNotFound(error)) throw nodeError(this.getNode(), error);
				}
				delete state.endpointId;
				delete state.endpointSecret;
				return false;
			},

			async create(this: IHookFunctions): Promise<boolean> {
				const client = await revokedClient(this);
				const url = this.getNodeWebhookUrl('default');
				if (!url) return false;
				try {
					const endpoint = await client.webhooks.endpoints.create({
						url,
						events: this.getNodeParameter('events') as string[],
						description: `n8n: ${this.getWorkflow().name ?? this.getWorkflow().id}`,
					});
					const state = this.getWorkflowStaticData('node') as EndpointState;
					state.endpointId = endpoint.id;
					state.endpointSecret = endpoint.secret;
					return true;
				} catch (error) {
					throw nodeError(this.getNode(), error);
				}
			},

			async delete(this: IHookFunctions): Promise<boolean> {
				const state = this.getWorkflowStaticData('node') as EndpointState;
				if (state.endpointId) {
					const client = await revokedClient(this);
					try {
						await client.webhooks.endpoints.delete(state.endpointId);
					} catch (error) {
						if (!isNotFound(error)) return false;
					}
				}
				delete state.endpointId;
				delete state.endpointSecret;
				return true;
			},
		},
	};

	async webhook(this: IWebhookFunctions): Promise<IWebhookResponseData> {
		const req = this.getRequestObject();
		const state = this.getWorkflowStaticData('node') as EndpointState;
		const refuse = (): IWebhookResponseData => {
			this.getResponseObject().status(401).end();
			return { noWebhookResponse: true };
		};
		if (!state.endpointSecret || !req.rawBody) return refuse();

		let event;
		try {
			event = await verifyWebhook({
				body: req.rawBody.toString('utf8'),
				signature: req.header(WEBHOOK_SIGNATURE_HEADER),
				secret: state.endpointSecret,
			});
		} catch {
			return refuse();
		}

		const output: IDataObject = { ...(event as unknown as IDataObject) };
		const options = this.getNodeParameter('options', {}) as { includeAnswer?: boolean };
		const data = event.data;
		if (options.includeAnswer && data.object === 'response' && 'request' in data && data.request) {
			const client = await revokedClient(this);
			const answers = await client.requests.responses(data.request);
			output.answer = (answers.find((a) => a.id === data.id) ?? null) as IDataObject | null;
		}

		return { workflowData: [this.helpers.returnJsonArray(output)] };
	}
}
