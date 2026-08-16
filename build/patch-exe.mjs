// Rebrands the Windows Electron executable: swaps the icon group and the
// version strings. Runs anywhere node runs — resedit is pure JS, so the
// Windows build never needs a Windows machine.
//
//   node patch-exe.mjs <in.exe> <icon.ico> <version> <out.exe>
//
// Expects resedit installed next to this script's caller (npm i resedit).

import { readFileSync, writeFileSync } from 'node:fs';
import * as resedit from 'resedit';

const [, , src, ico, version, out] = process.argv;
if (!src || !ico || !version || !out) {
  console.error('usage: patch-exe.mjs <in.exe> <icon.ico> <version> <out.exe>');
  process.exit(2);
}

const exe = resedit.NtExecutable.from(readFileSync(src), { ignoreCert: true });
const res = resedit.NtExecutableResource.from(exe);

const icon = resedit.Data.IconFile.from(readFileSync(ico));
resedit.Resource.IconGroupEntry.replaceIconsForResource(
  res.entries,
  resedit.Resource.IconGroupEntry.fromEntries(res.entries).map((e) => e.id)[0] ?? 1,
  1033,
  icon.icons.map((i) => i.data),
);

const versions = resedit.Resource.VersionInfo.fromEntries(res.entries);
if (versions.length) {
  const v = versions[0];
  const parts = version.split('.').map((n) => parseInt(n, 10) || 0);
  v.setFileVersion(parts[0] ?? 0, parts[1] ?? 0, parts[2] ?? 0, 0, 1033);
  v.setProductVersion(parts[0] ?? 0, parts[1] ?? 0, parts[2] ?? 0, 0, 1033);
  v.setStringValues(
    { lang: 1033, codepage: 1200 },
    {
      ProductName: 'ExecAI Studio',
      FileDescription: 'ExecAI Studio',
      CompanyName: 'ExecAI',
      LegalCopyright: 'ExecAI. Based on VSCodium (MIT).',
      OriginalFilename: 'ExecAI Studio.exe',
      InternalName: 'execai-studio',
    },
  );
  v.outputToResourceEntries(res.entries);
}

res.outputResource(exe);
writeFileSync(out, Buffer.from(exe.generate()));
console.log('patched', out);
