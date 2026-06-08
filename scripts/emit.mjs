// Emit an ambient-globals strudel.d.ts from Strudel's generated doc.json.
//
// Usage: node emit.mjs <doc.json> [overrides.mjs]
//
// doc.json is produced by Strudel's own JSDoc pipeline:
//   jsdoc packages/ --template node_modules/jsdoc-json -d doc.json -c jsdoc/jsdoc.config.json
//
// Why ambient globals: Strudel runs user code via Function() after dumping every
// package export onto globalThis (evalScope), so functions like note/s/jux are
// bare globals, not imports. The matching TS shape is `declare global { ... }`.
//
// Why permissive signatures: Strudel functions are auto-curried and exist both as
// free functions and Pattern methods, so precise inference is impossible. We emit
// each name as BOTH a global const and a Pattern method, with documented params
// (optional + ...rest) for nice hover, and let overrides.mjs hand-tune hot ones.

import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const [, , docPath, overridesPath] = process.argv;
if (!docPath) {
  console.error('usage: emit.mjs <doc.json> [overrides.mjs]');
  process.exit(1);
}

const doc = JSON.parse(fs.readFileSync(docPath, 'utf8'));
const docs = Array.isArray(doc) ? doc : doc.docs || [];

let ov = { signals: [], overrides: {} };
if (overridesPath && fs.existsSync(overridesPath)) {
  ov = await import(pathToFileURL(path.resolve(overridesPath)).href);
}
const signals = new Set(ov.signals || []);
const overrides = ov.overrides || {};

const ID = /^[A-Za-z_$][A-Za-z0-9_$]*$/;
const RESERVED = new Set(
  ('break case catch class const continue debugger default delete do else enum export ' +
    'extends false finally for function if import in instanceof new null return super ' +
    'switch this throw true try typeof var void while with')
    .split(' '),
);

// Global names already declared by lib.dom/lib.es (as var/function). Re-declaring
// them as `const` triggers TS2451/TS2300, so we keep them as Pattern methods only.
const GLOBAL_BUILTINS = new Set(
  ('focus blur name status length top parent self closed open close stop print find ' +
    'scroll scrollX scrollY scrollTo scrollBy alert confirm prompt atob btoa origin ' +
    'crypto performance history location navigator frames frameElement screen screenX ' +
    'screenY screenLeft screenTop innerWidth innerHeight outerWidth outerHeight ' +
    'devicePixelRatio event document console window fetch structuredClone reportError ' +
    'queueMicrotask requestAnimationFrame cancelAnimationFrame setTimeout clearTimeout ' +
    'setInterval clearInterval getComputedStyle matchMedia postMessage moveBy moveTo ' +
    'resizeBy resizeTo getSelection caches indexedDB localStorage sessionStorage ' +
    'isSecureContext speechSynthesis visualViewport customElements external')
    .split(/\s+/),
);

const TYPEMAP = {
  string: 'string', number: 'number', boolean: 'boolean', bool: 'boolean',
  Pattern: 'Pattern', function: 'Function', Function: 'Function',
  object: 'object', Object: 'object', void: 'void', '*': 'any', any: 'any',
};
function mapType(names) {
  if (!names || !names.length) return 'any';
  const mapped = [...new Set(names.map((n) => TYPEMAP[n] ?? 'any'))];
  return mapped.join(' | ');
}
function paramType(p) {
  const t = mapType(p.type && p.type.names);
  return t.split(' | ').includes('Pattern') ? t : `${t} | Pattern`;
}
function safeParam(name, i) {
  if (!name || name.includes('.') || !ID.test(name) || RESERVED.has(name)) return `arg${i}`;
  return name;
}
function cleanDoc(s) {
  if (!s) return '';
  return s
    .replace(/<\/?[^>]+>/g, '')
    .replace(/&quot;/g, '"').replace(/&amp;/g, '&').replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>').replace(/&#39;/g, "'").replace(/&nbsp;/g, ' ')
    .replace(/\r/g, '')
    .replace(/\n{3,}/g, '\n\n')
    .trim();
}

// Collect public API: global-scope functions + Pattern members, with synonyms.
const api = new Map();
function consider(d) {
  if (!d || !d.name || !ID.test(d.name)) return;
  if (['class', 'package', 'module', 'event', 'namespace', 'typedef'].includes(d.kind)) return;
  if (d.access === 'private' || d.name.startsWith('_')) return;
  const isGlobal = d.scope === 'global';
  const isPatternMember = d.memberof === 'Pattern';
  if (!isGlobal && !isPatternMember) return; // skip repl/MidiInput/etc internals
  const names = [d.name, ...(d.synonyms || [])];
  for (const nm of names) {
    if (!ID.test(nm)) continue;
    const cur = api.get(nm);
    if (cur) {
      const richer = (d.params?.length || 0) > (cur.params?.length || 0) || (!cur.desc && d.description);
      if (richer) api.set(nm, { name: nm, desc: d.description || cur.desc, params: d.params || cur.params, examples: d.examples || cur.examples });
      continue;
    }
    api.set(nm, { name: nm, desc: d.description || '', params: d.params || [], examples: d.examples || [] });
  }
}
for (const d of docs) consider(d);

function jsdocComment(desc, examples, indent) {
  const d = cleanDoc(desc);
  const out = [`${indent}/**`];
  if (d) d.split('\n').forEach((l) => out.push(`${indent} *${l ? ' ' + l : ''}`));
  (examples || []).slice(0, 3).forEach((ex) => {
    out.push(`${indent} * @example`);
    String(ex).split('\n').forEach((l) => out.push(`${indent} *${l ? ' ' + l : ''}`));
  });
  out.push(`${indent} */`);
  return out.join('\n');
}
function argsFromParams(params) {
  const out = [];
  const seen = new Set();
  (params || []).forEach((p, i) => {
    if (!p || !p.name || p.name.includes('.')) return;
    let nm = safeParam(p.name, i);
    let k = 2;
    const base = nm;
    while (seen.has(nm)) nm = base + k++;
    seen.add(nm);
    out.push(`${nm}?: ${paramType(p)}`);
  });
  out.push('...args: any[]');
  return out.join(', ');
}

const names = [...api.keys()].sort();
const methods = [];
const globals = [];
let nFn = 0, nSig = 0, nOvr = 0;

for (const nm of names) {
  const e = api.get(nm);
  if (signals.has(nm)) {
    globals.push(`${jsdocComment(e.desc, e.examples, '  ')}\n  const ${nm}: Pattern;`);
    nSig++;
    continue;
  }
  const ovr = overrides[nm];
  const args = ovr ? ovr.args : argsFromParams(e.params);
  if (ovr) nOvr++; else nFn++;
  const docG = jsdocComment(e.desc, e.examples, '  ');
  const docM = jsdocComment(e.desc, e.examples, '    ');
  if (!RESERVED.has(nm) && !GLOBAL_BUILTINS.has(nm)) {
    globals.push(`${docG}\n  const ${nm}: (${args}) => Pattern;`);
  }
  methods.push(`${docM}\n    ${nm}(${args}): Pattern;`);
}

const out = `// AUTO-GENERATED by strudel-types.nvim — do not edit by hand.
// Source: Strudel JSDoc (codeberg.org/uzu/strudel) -> doc.json -> scripts/emit.mjs
// Regenerate: scripts/gen-types.sh   (or :StrudelTypesUpdate in Neovim)
// Stats: ${nFn} auto fns, ${nOvr} hand-tuned, ${nSig} signals.

export {};

declare global {
  /** A Strudel pattern. Returned by every function; chain methods to transform it. */
  interface Pattern {
${methods.join('\n')}
  }

  /** The number-or-string-or-pattern values mini-notation accepts. */
  type StrudelInput = string | number | Pattern;

${globals.join('\n')}
}
`;
process.stdout.write(out);
console.error(`emit: ${names.length} names (${nFn} auto, ${nOvr} tuned, ${nSig} signals)`);
