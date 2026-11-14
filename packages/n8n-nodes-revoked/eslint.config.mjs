import { configWithoutCloudSupport } from '@n8n/node-cli/eslint';

// Self-hosted only. The SDK is the one dependency and has none of its own,
// and the SDKs are MPL-2.0 like the rest of packages/.
export default [
	...configWithoutCloudSupport,
	{
		files: ['package.json'],
		rules: {
			'@n8n/community-nodes/no-runtime-dependencies': 'off',
			'@n8n/community-nodes/valid-author': 'off',
			'n8n-nodes-base/community-package-json-license-not-default': 'off',
		},
	},
];
