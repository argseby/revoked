import {existsSync} from 'node:fs';
import {Config} from '@remotion/cli/config';

// Use an installed Chrome rather than letting Remotion download its own.
const chrome = process.env.REMOTION_CHROME ?? '/usr/bin/google-chrome-stable';
if (existsSync(chrome)) Config.setBrowserExecutable(chrome);

Config.setVideoImageFormat('jpeg');
Config.setJpegQuality(95);
Config.setCodec('h264');
Config.setCrf(16);
Config.setPixelFormat('yuv420p');
