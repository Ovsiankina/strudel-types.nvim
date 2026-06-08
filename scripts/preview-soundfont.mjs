// Produce a short audio file to preview a GM soundfont instrument.
//
// Usage: node preview-soundfont.mjs <preset> <out-file>
//   <preset>  e.g. 0000_JCLive_sf2_file  (a webaudiofont preset name)
//
// GM instruments are webaudiofont presets hosted as .js that embed one base64
// audio clip per note-zone. We fetch the preset, take a mid-range zone, and write
// its decoded clip (an MP3) to <out-file> for an audio player to play.
// Requires Node 18+ (global fetch).

import fs from 'node:fs';

const [, , preset, out] = process.argv;
if (!preset || !out) {
  console.error('usage: preview-soundfont.mjs <preset> <out-file>');
  process.exit(1);
}

const url = `https://felixroos.github.io/webaudiofontdata/sound/${preset}.js`;
let js;
try {
  const r = await fetch(url);
  if (!r.ok) { console.error('fetch failed: ' + r.status); process.exit(2); }
  js = await r.text();
} catch (e) {
  console.error('fetch error: ' + e.message);
  process.exit(2);
}

const files = [...js.matchAll(/file:\s*'([A-Za-z0-9+/=]+)'/g)].map((m) => m[1]);
if (!files.length) { console.error('no base64 zones found'); process.exit(3); }

// mid-range zone ~= a middle note, the most representative timbre
const b64 = files[Math.floor(files.length / 2)];
fs.writeFileSync(out, Buffer.from(b64, 'base64'));
console.error(`wrote ${out} (${files.length} zones, picked #${Math.floor(files.length / 2)})`);
