import { Resvg } from '@resvg/resvg-js';
import { readFile, writeFile, readdir, mkdir } from 'node:fs/promises';
import { join, resolve } from 'node:path';
const [input, output] = process.argv.slice(2);
if (!input || !output || resolve(input) === resolve(output)) throw new Error('Provide separate source and output directories.');
await mkdir(output, {recursive:true});
for (const name of (await readdir(input)).filter(name => name.endsWith('.png'))) {
  const bytes = await readFile(join(input,name));
  const png = bytes.subarray(0,8).toString('hex') === '89504e470d0a1a0a';
  let width, height;
  if (png) { width = bytes.readUInt32BE(16); height = bytes.readUInt32BE(20); }
  else if (bytes[0] === 0xff && bytes[1] === 0xd8) {
    const frames = new Set([0xc0,0xc1,0xc2,0xc3,0xc5,0xc6,0xc7,0xc9,0xca,0xcb,0xcd,0xce,0xcf]);
    let offset = 2;
    while (offset + 8 < bytes.length) {
      if (bytes[offset++] !== 0xff) throw new Error(`Invalid JPEG marker: ${name}`);
      while (bytes[offset] === 0xff) offset++;
      const marker = bytes[offset++];
      if (marker === 0xda || marker === 0xd9) break;
      if (marker >= 0xd0 && marker <= 0xd8) continue;
      const length = bytes.readUInt16BE(offset);
      if (length < 2 || offset + length > bytes.length) throw new Error(`Invalid JPEG segment: ${name}`);
      if (frames.has(marker)) { height = bytes.readUInt16BE(offset+3); width = bytes.readUInt16BE(offset+5); break; }
      offset += length;
    }
  }
  if (!width || !height) throw new Error(`Unsupported screenshot: ${name}`);
  const radius = Math.min(64, Math.round(Math.min(width,height) * 0.055));
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="0 0 ${width} ${height}"><defs><clipPath id="frame"><rect width="${width}" height="${height}" rx="${radius}"/></clipPath></defs><image href="data:image/${png?'png':'jpeg'};base64,${bytes.toString('base64')}" width="${width}" height="${height}" clip-path="url(#frame)"/></svg>`;
  await writeFile(join(output,name),new Resvg(svg).render().asPng());
  console.log(`${name}: ${width}×${height}, ${radius}px transparent rounded corners`);
}
