import { defineConfig } from 'tsdown';

export default defineConfig({
  entry: {
    index: 'src/index.ts',
    public: 'src/public.ts',
    connect: 'src/connect.ts',
    webhooks: 'src/webhooks.ts',
    identity: 'src/identity.ts',
    trust: 'src/trust.ts',
    sealed: 'src/sealed.ts',
  },
  format: ['esm', 'cjs'],
  platform: 'neutral',
  target: 'es2022',
  dts: true,
  sourcemap: true,
  clean: true,
});
