#!/usr/bin/env bun
// Inspect the already-built candidate without rerunning its custom build in a
// child process that cannot inherit Disk Guard's reservation descriptor.
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';

const root = process.cwd();
const source = await readFile('wrangler.toml', 'utf8');
const config = Bun.TOML.parse(source);
if (config.main !== 'build/_worker.js' || config.assets?.binding !== 'ASSETS') {
  throw new Error('Expected the canonical generated Worker and Workers Assets contract.');
}
await readFile(resolve(root, config.main));
await readFile(resolve(root, config.assets.directory, 'asset-manifest.json'));
const local = source
  .replace(/^\[build\]\n(?:(?!\[)[^\n]*\n)*/m, '')
  .replace(/^main = .*$/m, `main = ${JSON.stringify(resolve(root, config.main))}`)
  .replace(/^directory = .*$/m, `directory = ${JSON.stringify(resolve(root, config.assets.directory))}`)
  .replace(/^migrations_dir = .*$/m, `migrations_dir = ${JSON.stringify(resolve(root, config.d1_databases[0].migrations_dir))}`);
const parsed = Bun.TOML.parse(local);
if (parsed.build || parsed.name !== config.name || parsed.compatibility_date !== config.compatibility_date) {
  throw new Error('Local artifact configuration changed the runtime identity.');
}
const expected = structuredClone(config);
delete expected.build;
expected.main = resolve(root, config.main);
expected.assets.directory = resolve(root, config.assets.directory);
expected.d1_databases[0].migrations_dir = resolve(root, config.d1_databases[0].migrations_dir);
if (JSON.stringify(parsed) !== JSON.stringify(expected)) {
  throw new Error('Local snapshot must preserve every setting apart from the build hook and absolute local paths.');
}
await mkdir('var', { recursive: true });
await writeFile('var/wrangler.local.toml', local);
console.log('[local-config] Bound the canonical Worker and assets; provider-neutral bindings preserved.');
