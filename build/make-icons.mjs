// Builds the platform icon containers from branding/icon.png without any
// image tooling: both .ico (Vista+) and .icns (ic08) accept PNG data as is,
// so a 256×256 PNG is wrapped, never re-encoded.
//
//   node make-icons.mjs ico <icon.png> <out.ico>
//   node make-icons.mjs icns <icon.png> <out.icns>

import { readFileSync, writeFileSync } from 'node:fs';

const [, , kind, src, out] = process.argv;
if (!kind || !src || !out) {
  console.error('usage: make-icons.mjs ico|icns <icon.png> <out>');
  process.exit(2);
}
const png = readFileSync(src);

if (kind === 'ico') {
  // ICONDIR + one ICONDIRENTRY pointing at raw PNG. Width/height 0 = 256.
  const dir = Buffer.alloc(6 + 16);
  dir.writeUInt16LE(1, 2); // type: icon
  dir.writeUInt16LE(1, 4); // one image
  dir.writeUInt8(0, 6); // width 256
  dir.writeUInt8(0, 7); // height 256
  dir.writeUInt16LE(1, 10); // planes
  dir.writeUInt16LE(32, 12); // bpp
  dir.writeUInt32LE(png.length, 14); // bytes in resource
  dir.writeUInt32LE(22, 18); // offset of PNG data
  writeFileSync(out, Buffer.concat([dir, png]));
} else if (kind === 'icns') {
  // "icns" header + one ic08 (256×256 PNG) chunk.
  const chunk = Buffer.alloc(8);
  chunk.write('ic08', 0, 'ascii');
  chunk.writeUInt32BE(8 + png.length, 4);
  const total = Buffer.alloc(8);
  total.write('icns', 0, 'ascii');
  total.writeUInt32BE(8 + 8 + png.length, 4);
  writeFileSync(out, Buffer.concat([total, chunk, png]));
} else {
  console.error('unknown kind: ' + kind);
  process.exit(2);
}
