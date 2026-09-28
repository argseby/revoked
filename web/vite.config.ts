import { defineConfig } from 'vite';
import { svelte } from '@sveltejs/vite-plugin-svelte';

// In development the API is proxied, so the app is same-origin with the
// server exactly as it is behind the production reverse proxy.
const api = process.env.REVOKED_DEV_API ?? 'http://localhost:3000';

export default defineConfig({
  plugins: [svelte()],
  server: {
    proxy: {
      '/api': { target: api, changeOrigin: false },
      '/s/': { target: api, changeOrigin: false },
    },
  },
  build: {
    target: 'es2022',
    sourcemap: false,
  },
});
