#!/usr/bin/env bun
// Export the product's read-only Leptos pages, never the template's demo APIs.
// Run after verify.sh, against the qualified local Worker preview.
import { createHash } from 'node:crypto';
import { cp, mkdir, readFile, readdir, writeFile } from 'node:fs/promises';
import { join, resolve } from 'node:path';

const origin = process.argv[2] ?? 'http://127.0.0.1:57583';
const parsedOrigin = new URL(origin);
if (parsedOrigin.hostname !== '127.0.0.1' || parsedOrigin.protocol !== 'http:') {
  throw new Error('Export requires an explicit local Worker preview.');
}
const digest = value => createHash('sha256').update(value).digest('hex');
const hashScript = value => `'sha256-${createHash('sha256').update(value).digest('base64')}'`;
const assets = JSON.parse(await readFile('target/site/asset-manifest.json', 'utf8'));
for (const extension of ['js', 'wasm', 'css']) {
  const bytes = await readFile(join('target/site', assets[extension]));
  if (digest(bytes).slice(0, 16) !== assets.hashes[extension]) {
    throw new Error(`Built ${extension} does not match its fingerprint.`);
  }
}
const pages = new Map();
const scripts = new Set();
const queue = ['/'];
const seen = new Set(queue);
while (queue.length) {
  const path = queue.shift();
  const response = await fetch(new URL(path, origin), { redirect: 'error' });
  if (response.status !== 200 || !response.headers.get('content-type')?.includes('text/html')) {
    throw new Error(`Product route ${path} did not return HTML with status 200.`);
  }
  const html = (await response.text()).replace(/ nonce="[^"]*"/g, '');
  if (!html.includes('term-web') || /<form[\s>]/i.test(html)) {
    throw new Error(`Unexpected page content or form at ${path}.`);
  }
  for (const extension of ['js', 'wasm', 'css']) {
    if (!html.includes(assets[extension])) throw new Error(`Stale ${extension} reference at ${path}. Restart the local Worker after building.`);
  }
  pages.set(path, html);
  for (const match of html.matchAll(/<script\b([^>]*)>([\s\S]*?)<\/script>/g)) {
    if (!/\bsrc=/.test(match[1]) && match[2]) scripts.add(hashScript(match[2]));
  }
  for (const match of html.matchAll(/<a\b[^>]*href="([^"]*)"/g)) {
    const url = new URL(match[1].replaceAll('&amp;', '&'), origin);
    if (url.origin !== parsedOrigin.origin || url.pathname.startsWith('/images/')) continue;
    const route = url.pathname.replace(/\/$/, '') || '/';
    if (!/^\/(?:screens|privacy|docs(?:\/[a-z-]+)?)?$/.test(route)) {
      throw new Error(`Unexpected public route ${route}; review its export contract.`);
    }
    if (!seen.has(route)) { seen.add(route); queue.push(route); }
    if (seen.size > 20) throw new Error('Product export exceeded its route bound.');
  }
}
if (pages.size !== 10) throw new Error(`Expected the ten product pages, got ${pages.size}.`);
const missing = await fetch(new URL('/__pages_export_missing__', origin));
if (missing.status !== 404) throw new Error('The Worker must return a real 404.');
const missingHtml = (await missing.text()).replace(/ nonce="[^"]*"/g, '');
for (const match of missingHtml.matchAll(/<script\b([^>]*)>([\s\S]*?)<\/script>/g)) {
  if (!/\bsrc=/.test(match[1]) && match[2]) scripts.add(hashScript(match[2]));
}
const version = (await readFile('../VERSION', 'utf8')).trim();
const fingerprint = digest(JSON.stringify({ version, pages: [...pages], missingHtml, assets }));
const output = resolve(`var/pages/term-web-${version}-${fingerprint.slice(0, 16)}`);
await mkdir(output, { recursive: true });
for (const entry of await readdir('target/site', { withFileTypes: true })) {
  if (entry.name === '_headers' || entry.name.startsWith('_worker')) continue;
  await cp(join('target/site', entry.name), join(output, entry.name), { recursive: true });
}
for (const [path, html] of pages) {
  const destination = join(output, path === '/' ? '' : path.slice(1));
  await mkdir(destination, { recursive: true });
  await writeFile(join(destination, 'index.html'), html);
}
await writeFile(join(output, '404.html'), missingHtml);
const csp = `default-src 'self'; base-uri 'none'; object-src 'none'; frame-ancestors 'none'; form-action 'none'; img-src 'self' data:; connect-src 'self'; style-src 'self'; script-src 'self' 'wasm-unsafe-eval' ${[...scripts].sort().join(' ')};`;
await writeFile(join(output, '_headers'), `/*\n  Content-Security-Policy: ${csp}\n  Referrer-Policy: strict-origin-when-cross-origin\n  X-Content-Type-Options: nosniff\n  X-Frame-Options: DENY\n/pkg/*\n  Cache-Control: public, max-age=31536000, immutable\n`);
const files = [];
async function inventory(directory, prefix = '') {
  for (const entry of (await readdir(directory, { withFileTypes: true })).sort((a, b) => a.name.localeCompare(b.name))) {
    const path = prefix + entry.name;
    if (entry.isDirectory()) await inventory(join(directory, entry.name), path + '/');
    else files.push({ path, sha256: digest(await readFile(join(directory, entry.name))) });
  }
}
await inventory(output);
const receipt = { version, fingerprint, output, routes: [...pages.keys()].sort(), files, artifactSha256: digest(JSON.stringify(files)) };
await writeFile('var/pages-export.json', JSON.stringify(receipt, null, 2) + '\n');
console.log(JSON.stringify({ output, routes: receipt.routes, files: files.length, artifactSha256: receipt.artifactSha256 }, null, 2));
