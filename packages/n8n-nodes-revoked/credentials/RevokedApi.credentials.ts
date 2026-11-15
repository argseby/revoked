import type {
	IAuthenticateGeneric,
	Icon,
	ICredentialTestRequest,
	ICredentialType,
	INodeProperties,
} from 'n8n-workflow';

export class RevokedApi implements ICredentialType {
	name = 'revokedApi';

	displayName = 'Revoked API';

	icon: Icon = { light: 'file:../nodes/Revoked/revoked.svg', dark: 'file:../nodes/Revoked/revoked.dark.svg' };

	documentationUrl = 'https://docs.revoked.link/api/authentication/';

	properties: INodeProperties[] = [
		{
			displayName: 'Server',
			name: 'server',
			type: 'string',
			default: '',
			placeholder: 'https://api.example.com',
			required: true,
			description: 'Origin of the Revoked server',
		},
		{
			displayName: 'API Key',
			name: 'apiKey',
			type: 'string',
			typeOptions: { password: true },
			default: '',
			required: true,
			description:
				'Permissions and vault sections are set when the key is created in the app. Keys never reach the whole vault.',
		},
	];

	authenticate: IAuthenticateGeneric = {
		type: 'generic',
		properties: {
			headers: {
				'X-API-Key': '={{$credentials.apiKey}}',
			},
		},
	};

	test: ICredentialTestRequest = {
		request: {
			baseURL: '={{$credentials.server.replace(/\\/+$/, "")}}',
			url: '/api/me',
		},
	};
}
