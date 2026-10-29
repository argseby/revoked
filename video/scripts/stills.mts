// Renders contact-sheet stills: node scripts/stills.mts <outDir> <comp>:<frame>[,<frame>...] ...
import {existsSync} from 'node:fs';
import path from 'node:path';
import {bundle} from '@remotion/bundler';
import {renderStill, selectComposition} from '@remotion/renderer';

const [outDir, ...specs] = process.argv.slice(2);
const chrome = process.env.REMOTION_CHROME ?? '/usr/bin/google-chrome-stable';
const browserExecutable = existsSync(chrome) ? chrome : null;
const serveUrl = await bundle({entryPoint: path.resolve('src/index.ts')});

for (const spec of specs) {
  const [id, frames] = spec.split(':');
  const composition = await selectComposition({serveUrl, id, browserExecutable});
  for (const frame of frames.split(',').map(Number)) {
    const output = path.join(outDir, `${id}-${String(frame).padStart(4, '0')}.png`);
    await renderStill({composition, serveUrl, frame, output, browserExecutable, scale: 0.5});
    console.log(output);
  }
}
