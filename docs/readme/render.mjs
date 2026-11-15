// Renders the README images: node docs/readme/render.mjs
// Needs Google Chrome or Chromium and the Inter and Noto Sans Mono fonts installed.
import { execFileSync } from 'node:child_process';
import { mkdirSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const out = resolve(here, '../assets/readme');
const chrome = process.env.CHROME ?? 'google-chrome-stable';
const pages = { hero: 600, 'how-it-works': 456, 'why-a-link': 470, products: 802 };

mkdirSync(out, { recursive: true });
for (const [name, height] of Object.entries(pages)) {
  const src = join(here, `${name}.html`);
  for (const theme of ['light', 'dark']) {
    const file = join(out, `${name}-${theme}.png`);
    execFileSync(chrome, [
      '--headless=new', '--disable-gpu', '--hide-scrollbars',
      '--force-device-scale-factor=2', '--default-background-color=00000000',
      `--window-size=1280,${height}`, `--screenshot=${file}`,
      `${pathToFileURL(src).href}#${theme}`,
    ], { stdio: 'ignore' });
    console.log(file);
  }
}
