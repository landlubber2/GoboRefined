#!/usr/bin/env node
'use strict';

// tools/bump-kernel.js — Check or update the pinned LTS kernel version in spin/kernel-version
// and build/sources.manifest using kernel.org's official releases.json + sha256sums.asc (P6).
// Zero external npm dependencies.
//
// Usage:
//   node tools/bump-kernel.js                  (dry-run: check latest in current LTS series)
//   node tools/bump-kernel.js --version 6.12.119
//   node tools/bump-kernel.js --apply          (update spin/kernel-version and build/sources.manifest)

const fs = require('fs');
const path = require('path');

const REPO = path.resolve(__dirname, '..');
const KVER_PATH = path.join(REPO, 'spin', 'kernel-version');
const MANIFEST_PATH = path.join(REPO, 'build', 'sources.manifest');
const UA = 'goborefined-bump-kernel/1.0';

function parseArgs(argv) {
  const opts = { version: null, apply: false };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--version') opts.version = argv[++i];
    else if (a === '--apply') opts.apply = true;
    else if (a === '--dry-run') opts.apply = false;
    else if (a === '-h' || a === '--help') {
      console.log('Usage: node tools/bump-kernel.js [--version X.Y.Z] [--dry-run | --apply]');
      process.exit(0);
    } else {
      console.error(`bump-kernel: unknown option '${a}'`);
      process.exit(1);
    }
  }
  return opts;
}

async function fetchText(url, timeoutMs = 20000) {
  const r = await fetch(url, {
    headers: { 'User-Agent': UA },
    signal: AbortSignal.timeout(timeoutMs),
  });
  if (!r.ok) throw new Error(`HTTP ${r.status} for ${url}`);
  return r.text();
}

async function main() {
  const opts = parseArgs(process.argv.slice(2));
  const curVer = fs.readFileSync(KVER_PATH, 'utf8').trim().split(/\r?\n/)[0].trim();
  if (!/^\d+\.\d+\.\d+$/.test(curVer)) {
    throw new Error(`unexpected spin/kernel-version: '${curVer}'`);
  }
  const curSeries = curVer.split('.').slice(0, 2).join('.');

  const [releases, eolList] = await Promise.all([
    fetchText('https://www.kernel.org/releases.json').then(JSON.parse),
    fetchText('https://endoflife.date/api/linux.json').then(JSON.parse).catch(() => []),
  ]);

  let targetVer = opts.version;
  const relEntry = (releases.releases || []).find(r => r.version.startsWith(curSeries + '.'));
  if (!targetVer) {
    if (!relEntry) throw new Error(`no kernel.org release entry found for series ${curSeries}`);
    targetVer = relEntry.version;
  }
  if (!/^\d+\.\d+\.\d+$/.test(targetVer)) {
    throw new Error(`invalid target kernel version: '${targetVer}'`);
  }

  const targetMajor = targetVer.split('.')[0];
  const targetSeries = targetVer.split('.').slice(0, 2).join('.');
  const eolEntry = Array.isArray(eolList) ? eolList.find(x => x.cycle === targetSeries) : null;
  const eolDate = eolEntry && typeof eolEntry.eol === 'string' ? eolEntry.eol : 'unknown';

  const tarName = `linux-${targetVer}.tar.xz`;
  const sumsUrl = `https://cdn.kernel.org/pub/linux/kernel/v${targetMajor}.x/sha256sums.asc`;
  const tarUrl = `https://cdn.kernel.org/pub/linux/kernel/v${targetMajor}.x/${tarName}`;

  const sumsTxt = await fetchText(sumsUrl, 30000);
  const sumRe = new RegExp(`^([0-9a-f]{64})\\s+${tarName.replace(/\./g, '\\.')}$`, 'm');
  const m = sumsTxt.match(sumRe);
  if (!m) {
    throw new Error(`${tarName} not found in ${sumsUrl}`);
  }
  const sha256 = m[1];

  console.log(`Current kernel : ${curVer} (series ${curSeries})`);
  console.log(`Target kernel  : ${targetVer} (series ${targetSeries}, EOL ${eolDate})`);
  if (relEntry && relEntry.version === targetVer && relEntry.released?.isodate) {
    console.log(`Release date   : ${relEntry.released.isodate}`);
  }
  console.log(`Archive URL    : ${tarUrl}`);
  console.log(`Official sha256: ${sha256}`);

  if (targetVer === curVer) {
    console.log('Status         : already pinned to this kernel version (no changes needed).');
    return;
  }

  if (targetSeries !== curSeries) {
    console.log(`WARNING        : series change (${curSeries} -> ${targetSeries}) — check spin/build-programs.sh version regex and GoboHide patch!`);
  }

  if (!opts.apply) {
    console.log('');
    console.log('Dry run only (no files modified). Re-run with --apply to update:');
    console.log('  - spin/kernel-version');
    console.log('  - build/sources.manifest');
    return;
  }

  // Update spin/kernel-version
  fs.writeFileSync(KVER_PATH, targetVer + '\n', 'utf8');

  // Update linux line in build/sources.manifest while preserving comments and surrounding lines
  const manifestRaw = fs.readFileSync(MANIFEST_PATH, 'utf8');
  const eolChar = manifestRaw.includes('\r\n') ? '\r\n' : '\n';
  let replaced = 0;
  const newLines = manifestRaw.split(/\r?\n/).map(line => {
    if (/^linux\s+/.test(line)) {
      replaced++;
      return `linux           ${targetVer.padEnd(13)} ${tarName.padEnd(42)} ${sha256}  GPL-2.0-only         ${tarUrl}`;
    }
    return line;
  });
  if (replaced !== 1) {
    throw new Error(`expected exactly 1 'linux' line in build/sources.manifest, found ${replaced}`);
  }
  fs.writeFileSync(MANIFEST_PATH, newLines.join(eolChar), 'utf8');

  console.log('');
  console.log(`Updated spin/kernel-version and build/sources.manifest (${curVer} -> ${targetVer}).`);
  console.log('Next steps:');
  console.log('  1. bash tools/pipeline build --mode kernel-check     # 2-min GoboHide patch dry-run');
  console.log('  2. bash tools/pipeline release --version <V> --mode kernel');
}

main().catch(err => {
  console.error('bump-kernel: ERROR:', err.message);
  process.exit(1);
});
