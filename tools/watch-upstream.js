#!/usr/bin/env node
'use strict';

// tools/watch-upstream.js — Weekly upstream version & security watcher for GoboRefined (P1).
// Zero external npm dependencies (uses Node.js built-in fetch/fs/path/child_process).
//
// Inputs:
//   build/sources.manifest   — packages we build/fetch
//   build/base-inventory.txt — complete image inventory (generated in P0)
//   tools/watch-rules.json   — tier-1 packages, Debian source mapping, ignore rules
//
// Usage:
//   node tools/watch-upstream.js [--out FILE] [--no-cache] [--notify] [--json] [--exit-on-red]

const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const REPO = path.resolve(__dirname, '..');
const MANIFEST_PATH = path.join(REPO, 'build', 'sources.manifest');
const INVENTORY_PATH = path.join(REPO, 'build', 'base-inventory.txt');
const RULES_PATH = path.join(__dirname, 'watch-rules.json');
const WATCH_DIR = path.join(REPO, 'watch');
const CACHE_DIR = path.join(WATCH_DIR, '.cache');
const UA = 'goborefined-watch/1.0';

function parseArgs(argv) {
  const opts = { out: null, noCache: false, notify: false, json: false, exitOnRed: false };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--out') opts.out = argv[++i];
    else if (a === '--no-cache') opts.noCache = true;
    else if (a === '--notify') opts.notify = true;
    else if (a === '--json') opts.json = true;
    else if (a === '--exit-on-red') opts.exitOnRed = true;
    else if (a === '-h' || a === '--help') {
      console.log('Usage: node tools/watch-upstream.js [--out FILE] [--no-cache] [--notify] [--json] [--exit-on-red]');
      process.exit(0);
    } else {
      console.error(`watch-upstream: unknown option '${a}'`);
      process.exit(1);
    }
  }
  return opts;
}

function readManifest() {
  const map = new Map();
  const lines = fs.readFileSync(MANIFEST_PATH, 'utf8').split(/\r?\n/);
  for (const raw of lines) {
    const line = raw.trim();
    if (!line || line.startsWith('#')) continue;
    const parts = line.split(/\s+/);
    if (parts.length < 6) continue;
    const [step, version, file, sha256, licence, url] = parts;
    // Keep first entry per step (for rust/pymods/vulkan which list multiple files)
    if (!map.has(step)) map.set(step, { step, version, file, sha256, licence, url });
  }
  return map;
}

function readInventory() {
  const list = [];
  const lines = fs.readFileSync(INVENTORY_PATH, 'utf8').split(/\r?\n/);
  for (const raw of lines) {
    const line = raw.trim();
    if (!line || line.startsWith('#')) continue;
    const parts = line.split('\t');
    if (parts.length < 6) continue;
    const [program, version, origin, upstream, lane, notes] = parts;
    list.push({ program, version, origin, upstream, lane, notes });
  }
  return list;
}

// Generic dotted/alphanumeric version comparator (handles 1.8.31p1, 1.1.1d, 6.12.117, 153.7.0esr, 7.0.10_4)
function tokenizeVer(v) {
  return String(v || '')
    .replace(/^[vV]/, '')
    .replace(/esr$/i, '')
    .split(/[^0-9A-Za-z]+/)
    .filter(Boolean)
    .flatMap(tok => tok.match(/\d+|[A-Za-z]+/g) || []);
}

function cmpVer(a, b) {
  const ta = tokenizeVer(a);
  const tb = tokenizeVer(b);
  const n = Math.max(ta.length, tb.length);
  for (let i = 0; i < n; i++) {
    const xa = ta[i];
    const xb = tb[i];
    if (xa === undefined) return /^\d+$/.test(xb) ? -1 : -1;
    if (xb === undefined) return /^\d+$/.test(xa) ? 1 : 1;
    const na = /^\d+$/.test(xa);
    const nb = /^\d+$/.test(xb);
    if (na && nb) {
      const diff = Number(xa) - Number(xb);
      if (diff !== 0) return diff < 0 ? -1 : 1;
    } else if (na !== nb) {
      return na ? 1 : -1;
    } else {
      const diff = xa.localeCompare(xb);
      if (diff !== 0) return diff < 0 ? -1 : 1;
    }
  }
  return 0;
}

// Strip Debian epoch ("1:"), Debian revision ("-2+deb12u1"), "+dfsg", "~bpo", etc. to get upstream version
function debianUpstreamVer(debVer) {
  if (!debVer || debVer === '0') return null;
  let v = String(debVer).replace(/^\d+:/, '');
  v = v.replace(/-[^-]+$/, '');
  v = v.replace(/[+~.](dfsg|ds|deb|repack|git|svn|hg|nmu|ubuntu|real|clean).*$/i, '');
  return v || null;
}

async function fetchText(url, timeoutMs = 20000) {
  const r = await fetch(url, {
    headers: { 'User-Agent': UA, Accept: '*/*' },
    signal: AbortSignal.timeout(timeoutMs),
  });
  if (!r.ok) throw new Error(`HTTP ${r.status}`);
  return r.text();
}

async function fetchCachedJson(name, url, cacheHours, noCache) {
  fs.mkdirSync(CACHE_DIR, { recursive: true });
  const cachePath = path.join(CACHE_DIR, name);
  if (!noCache && fs.existsSync(cachePath)) {
    const ageMs = Date.now() - fs.statSync(cachePath).mtimeMs;
    if (ageMs < cacheHours * 3600 * 1000) {
      return { data: JSON.parse(fs.readFileSync(cachePath, 'utf8')), cached: true };
    }
  }
  const txt = await fetchText(url, 45000);
  const data = JSON.parse(txt);
  fs.writeFileSync(cachePath, txt, 'utf8');
  return { data, cached: false };
}

function daysUntil(isoDate) {
  const target = Date.parse(isoDate);
  if (Number.isNaN(target)) return null;
  return Math.floor((target - Date.now()) / (86400 * 1000));
}

function sendWindowsNotification(redCount, yellowCount, reportPath) {
  if (process.platform !== 'win32') return;
  const title = `GoboRefined: ${redCount} red security item${redCount === 1 ? '' : 's'}`;
  const msg = `${redCount} red, ${yellowCount} yellow. Report: ${path.basename(reportPath)}`;
  const ps = `
Add-Type -AssemblyName System.Windows.Forms
$n = New-Object System.Windows.Forms.NotifyIcon
$n.Icon = [System.Drawing.SystemIcons]::Warning
$n.BalloonTipIcon = [System.Windows.Forms.ToolTipIcon]::Warning
$n.BalloonTipTitle = '${title.replace(/'/g, "''")}'
$n.BalloonTipText = '${msg.replace(/'/g, "''")}'
$n.Visible = $true
$n.ShowBalloonTip(8000)
Start-Sleep -Seconds 2
$n.Dispose()
`;
  try {
    execFileSync('powershell.exe', ['-NoProfile', '-WindowStyle', 'Hidden', '-Command', ps], { timeout: 10000 });
  } catch (_) {
    // Non-fatal if headless or restricted
  }
}

async function checkUpstreams(manifest, rules) {
  const red = [];
  const yellow = [];
  const ok = [];
  const warnings = [];
  const meta = {};

  const jobs = [
    // 1. Firefox ESR
    (async () => {
      const cur = manifest.get('firefox')?.version || 'unknown';
      try {
        const d = JSON.parse(await fetchText('https://product-details.mozilla.org/1.0/firefox_versions.json'));
        const latest = d.FIREFOX_ESR || '';
        meta.firefox = { installed: cur, latest, next: d.FIREFOX_ESR_NEXT || '' };
        if (latest && cmpVer(cur, latest) < 0) {
          red.push({
            pkg: 'Firefox ESR',
            installed: cur,
            latest,
            lane: 'browser',
            detail: `New Mozilla Firefox ESR release available (${cur} -> ${latest})`,
          });
        } else {
          ok.push(`Firefox ESR ${cur} (up to date)`);
        }
      } catch (e) {
        warnings.push(`Firefox ESR check failed: ${e.message}`);
      }
    })(),

    // 2. Linux kernel (version + LTS EOL)
    (async () => {
      const cur = manifest.get('linux')?.version || 'unknown';
      const series = cur.split('.').slice(0, 2).join('.');
      try {
        const [rel, eolList] = await Promise.all([
          fetchText('https://www.kernel.org/releases.json').then(JSON.parse),
          fetchText('https://endoflife.date/api/linux.json').then(JSON.parse).catch(() => []),
        ]);
        const match = (rel.releases || []).find(r => r.version.startsWith(series + '.'));
        const eolEntry = Array.isArray(eolList) ? eolList.find(x => x.cycle === series) : null;
        const eolDate = eolEntry && typeof eolEntry.eol === 'string' ? eolEntry.eol : null;
        const days = eolDate ? daysUntil(eolDate) : null;
        const latest = match ? match.version : (eolEntry?.latest || '');
        const relDate = match?.released?.isodate || eolEntry?.latestReleaseDate || '';
        meta.kernel = { installed: cur, series, latest, released: relDate, eol: eolDate, eolDays: days };

        if (match?.iseol || (days !== null && days <= (rules.kernel_eol_warn_days || 60))) {
          red.push({
            pkg: `Linux ${series} LTS`,
            installed: cur,
            latest: latest || 'EOL',
            lane: 'kernel',
            detail: `Kernel ${series} LTS EOL ${eolDate || 'reached'} (${days !== null ? `${days} days left` : 'EOL'})`,
          });
        }
        if (latest && cmpVer(cur, latest) < 0) {
          yellow.push({
            pkg: 'Linux kernel',
            installed: cur,
            latest,
            lane: 'kernel',
            detail: `New ${series} LTS point release (${relDate || 'recent'}; EOL ${eolDate || 'unknown'})`,
          });
        } else {
          ok.push(`Linux ${cur} (up to date; EOL ${eolDate || 'unknown'})`);
        }
      } catch (e) {
        warnings.push(`Kernel check failed: ${e.message}`);
      }
    })(),

    // 3. Mesa
    (async () => {
      const cur = manifest.get('mesa')?.version || 'unknown';
      const series = cur.split('.').slice(0, 2).join('.');
      try {
        const html = await fetchText('https://archive.mesa3d.org/');
        const vers = [...new Set([...html.matchAll(/mesa-(\d+\.\d+\.\d+)\.tar\.xz/g)].map(m => m[1]))].sort(cmpVer);
        const latestAll = vers[vers.length - 1] || '';
        const seriesVers = vers.filter(v => v.startsWith(series + '.'));
        const latestSeries = seriesVers[seriesVers.length - 1] || '';
        meta.mesa = { installed: cur, latestSeries, latestAll };
        if (latestSeries && cmpVer(cur, latestSeries) < 0) {
          yellow.push({
            pkg: 'Mesa',
            installed: cur,
            latest: latestSeries,
            lane: 'full-release',
            detail: `New ${series}.x point release (newest major: ${latestAll})`,
          });
        } else if (latestAll && cmpVer(cur, latestAll) < 0) {
          yellow.push({
            pkg: 'Mesa',
            installed: cur,
            latest: latestAll,
            lane: 'full-release',
            detail: `New Mesa major series available (test on real PC/laptop before shipping)`,
          });
        } else {
          ok.push(`Mesa ${cur} (up to date)`);
        }
      } catch (e) {
        warnings.push(`Mesa check failed: ${e.message}`);
      }
    })(),

    // 4. CA bundle
    (async () => {
      const cur = manifest.get('ca-bundle')?.version || 'unknown';
      try {
        const html = await fetchText('https://curl.se/docs/caextract.html');
        const dates = [...new Set([...html.matchAll(/cacert-(\d{4}-\d{2}-\d{2})\.pem/g)].map(m => m[1]))].sort();
        const latest = dates[dates.length - 1] || '';
        meta.caBundle = { installed: cur, latest };
        if (latest && latest > cur) {
          yellow.push({
            pkg: 'CA certificates',
            installed: cur,
            latest,
            lane: 'security-pack',
            detail: `New Mozilla CA bundle on curl.se (${cur} -> ${latest})`,
          });
        } else {
          ok.push(`CA bundle ${cur} (up to date)`);
        }
      } catch (e) {
        warnings.push(`CA bundle check failed: ${e.message}`);
      }
    })(),

    // 5. Intel microcode
    (async () => {
      const cur = manifest.get('intel-microcode')?.version || 'unknown';
      try {
        const d = JSON.parse(
          await fetchText('https://api.github.com/repos/intel/Intel-Linux-Processor-Microcode-Data-Files/releases/latest')
        );
        const latest = String(d.tag_name || '').replace(/^microcode-/, '');
        meta.intelMicrocode = { installed: cur, latest };
        if (latest && latest > cur) {
          yellow.push({
            pkg: 'Intel microcode',
            installed: cur,
            latest,
            lane: 'full-release',
            detail: `New Intel microcode release (${cur} -> ${latest})`,
          });
        } else {
          ok.push(`Intel microcode ${cur} (up to date)`);
        }
      } catch (e) {
        warnings.push(`Intel microcode check failed: ${e.message}`);
      }
    })(),

    // 6. linux-firmware
    (async () => {
      const cur = manifest.get('linux-firmware')?.version || 'unknown';
      try {
        const html = await fetchText('https://mirrors.edge.kernel.org/pub/linux/kernel/firmware/');
        const vers = [...new Set([...html.matchAll(/linux-firmware-(\d{8})\.tar\.xz/g)].map(m => m[1]))].sort();
        const latest = vers[vers.length - 1] || '';
        meta.linuxFirmware = { installed: cur, latest };
        if (latest && latest > cur) {
          yellow.push({
            pkg: 'linux-firmware',
            installed: cur,
            latest,
            lane: 'full-release',
            detail: `New kernel.org firmware snapshot (${cur} -> ${latest})`,
          });
        } else {
          ok.push(`linux-firmware ${cur} (up to date)`);
        }
      } catch (e) {
        warnings.push(`linux-firmware check failed: ${e.message}`);
      }
    })(),

    // 7. SOF firmware
    (async () => {
      const cur = manifest.get('sof-firmware')?.version || 'unknown';
      try {
        const d = JSON.parse(await fetchText('https://api.github.com/repos/thesofproject/sof-bin/releases/latest'));
        const latest = String(d.tag_name || '').replace(/^v/, '');
        meta.sofFirmware = { installed: cur, latest };
        if (latest && cmpVer(cur, latest) < 0) {
          yellow.push({
            pkg: 'SOF firmware',
            installed: cur,
            latest,
            lane: 'full-release',
            detail: `New sof-bin release (${cur} -> ${latest})`,
          });
        } else {
          ok.push(`SOF firmware ${cur} (up to date)`);
        }
      } catch (e) {
        warnings.push(`SOF firmware check failed: ${e.message}`);
      }
    })(),
  ];

  await Promise.all(jobs);
  return { red, yellow, ok, warnings, meta };
}

async function checkCves(inventory, rules, opts) {
  const red = [];
  const yellow = [];
  const grey = [];
  const warnings = [];
  const cacheHours = rules.cache_hours ?? 12;

  let kevSet = new Set();
  let debData = null;
  let cacheInfo = {};

  try {
    const kevRes = await fetchCachedJson(
      'cisa-kev.json',
      'https://www.cisa.gov/sites/default/files/feeds/known_exploited_vulnerabilities.json',
      cacheHours,
      opts.noCache
    );
    for (const v of kevRes.data.vulnerabilities || []) {
      if (v.cveID) kevSet.add(v.cveID);
    }
    cacheInfo.kev = kevRes.cached ? 'cached' : 'fresh';
  } catch (e) {
    warnings.push(`CISA KEV fetch failed: ${e.message}`);
  }

  try {
    const debRes = await fetchCachedJson(
      'debian-security-tracker.json',
      'https://security-tracker.debian.org/tracker/data/json',
      cacheHours,
      opts.noCache
    );
    debData = debRes.data;
    cacheInfo.debian = debRes.cached ? 'cached' : 'fresh';
  } catch (e) {
    warnings.push(`Debian security tracker fetch failed: ${e.message}`);
    return { red, yellow, grey, warnings, cacheInfo };
  }

  const tier1 = new Set(rules.tier1_packages || []);
  const ignoreCves = new Map((rules.ignore_cves || []).map(x => [x.cve, x.reason]));
  const ignorePkgs = new Map((rules.ignore_packages || []).map(x => [x.upstream, x.reason]));
  const debMap = rules.debian_source_map || {};

  // Deduplicate inventory by upstream name (preferring non-stub active entries)
  const byUpstream = new Map();
  for (const item of inventory) {
    if (item.upstream === '-' || item.version === '-') continue;
    if (!byUpstream.has(item.upstream)) byUpstream.set(item.upstream, item);
  }

  const URG_RANK = { high: 3, medium: 2, 'not yet assigned': 2, low: 1, unimportant: 0 };

  for (const [upstream, debSrc] of Object.entries(debMap)) {
    const item = byUpstream.get(upstream);
    if (!item) continue;
    if (ignorePkgs.has(upstream)) {
      grey.push(`${item.program} ${item.version} (ignored: ${ignorePkgs.get(upstream)})`);
      continue;
    }
    const pkgCves = debData[debSrc];
    if (!pkgCves) continue;

    let kevHits = [];
    let highHits = [];
    let stdHits = [];
    let lowCount = 0;
    let ignoredCount = 0;
    let highestFixed = '';

    for (const [cveId, entry] of Object.entries(pkgCves)) {
      if (!cveId.startsWith('CVE-')) continue;
      if (ignoreCves.has(cveId)) {
        ignoredCount++;
        continue;
      }

      const rels = entry.releases || {};
      // Use sid (unstable) first for true upstream fixed_version (avoids Debian backport version skew).
      // Fall back to forky/trixie/bookworm only if sid is missing.
      const primaryRel = rels.sid || rels.forky || rels.trixie || rels.bookworm;
      if (!primaryRel) continue;

      let affectsInstalled = false;
      let fixedHere = null;
      if (primaryRel.status === 'resolved' && primaryRel.fixed_version) {
        if (primaryRel.fixed_version === '0') continue; // never affected
        const upFixed = debianUpstreamVer(primaryRel.fixed_version);
        if (upFixed && cmpVer(item.version, upFixed) < 0) {
          affectsInstalled = true;
          fixedHere = upFixed;
        }
      } else if (primaryRel.status === 'open') {
        const pUrg = String(primaryRel.urgency || '').replace(/\*\*$/, '');
        if ((URG_RANK[pUrg] ?? 0) >= 2) {
          affectsInstalled = true;
        }
      }

      if (!affectsInstalled) continue;

      // Determine highest urgency across active releases (Debian marks DSA-level CVEs "not yet assigned")
      let maxUrg = -1;
      let maxUrgName = 'unimportant';
      for (const relName of ['sid', 'forky', 'trixie', 'bookworm']) {
        const rel = rels[relName];
        if (!rel) continue;
        const urg = String(rel.urgency || '').replace(/\*\*$/, '');
        if (urg === 'end-of-life') continue;
        const rank = URG_RANK[urg] ?? 0;
        if (rank > maxUrg) {
          maxUrg = rank;
          maxUrgName = urg;
        }
      }

      if (fixedHere && (!highestFixed || cmpVer(highestFixed, fixedHere) < 0)) {
        highestFixed = fixedHere;
      }

      const isKev = kevSet.has(cveId);
      if (isKev) kevHits.push(cveId);
      else if (maxUrgName === 'high') highHits.push(cveId);
      else if (maxUrg >= 2) stdHits.push(cveId);
      else lowCount++;
    }

    const totalSignificant = kevHits.length + highHits.length + stdHits.length;
    if (totalSignificant === 0) {
      if (lowCount > 0 || ignoredCount > 0) {
        grey.push(`${item.program} ${item.version} (${lowCount} low/unimportant, ${ignoredCount} ignored)`);
      }
      continue;
    }

    // Sort newest CVEs first
    kevHits.sort().reverse();
    highHits.sort().reverse();
    stdHits.sort().reverse();

    const sample = [...kevHits.slice(0, 3), ...highHits.slice(0, 2), ...stdHits.slice(0, 2)].slice(0, 4).join(', ');
    const row = {
      program: item.program,
      upstream,
      installed: item.version,
      origin: item.origin,
      lane: item.lane,
      kev: kevHits.length,
      high: highHits.length,
      std: stdHits.length,
      low: lowCount,
      fixed: highestFixed || 'open',
      sample,
      isTier1: tier1.has(upstream),
    };

    if (row.kev > 0 || (row.isTier1 && (row.high > 0 || row.std > 0))) {
      red.push(row);
    } else if (row.high > 0 || row.std > 0) {
      yellow.push(row);
    } else {
      grey.push(`${item.program} ${item.version} (${lowCount} low)`);
    }
  }

  // Sort Red: manifest packages first, then KEV desc, Tier1 first, total desc
  red.sort((a, b) =>
    ((b.origin !== 'base') - (a.origin !== 'base')) ||
    (b.kev - a.kev) ||
    (b.isTier1 - a.isTier1) ||
    ((b.high + b.std) - (a.high + a.std))
  );
  yellow.sort((a, b) => ((b.high + b.std) - (a.high + a.std)) || a.program.localeCompare(b.program));

  return { red, yellow, grey, warnings, cacheInfo };
}

function buildMarkdown(dateStr, upstreamRes, cveRes, manifest, inventory) {
  const lines = [];
  const totalRed = upstreamRes.red.length + cveRes.red.length;
  const totalYellow = upstreamRes.yellow.length + cveRes.yellow.length;

  lines.push(`# GoboRefined Upstream Watch — ${dateStr}`);
  lines.push('');
  lines.push(`- **Generated (UTC):** ${new Date().toISOString()}`);
  lines.push(`- **Inputs:** \`build/sources.manifest\` (${manifest.size} steps), \`build/base-inventory.txt\` (${inventory.length} entries)`);
  lines.push(`- **Feeds:** Debian Security Tracker (${cveRes.cacheInfo.debian || 'err'}), CISA KEV (${cveRes.cacheInfo.kev || 'err'}), kernel.org, endoflife.date, Mozilla, Mesa, curl.se, GitHub`);
  lines.push(`- **Summary:** **${totalRed} Red**, **${totalYellow} Yellow**, ${cveRes.grey.length} Grey, ${upstreamRes.ok.length} up-to-date tracked feeds`);
  if (upstreamRes.meta.kernel) {
    const k = upstreamRes.meta.kernel;
    lines.push(`- **Kernel LTS status:** \`${k.installed}\` (latest \`${k.latest || '?'}\`, series \`${k.series}\` EOL \`${k.eol || 'unknown'}\`${k.eolDays !== null ? `, ${k.eolDays} days left` : ''})`);
  }
  lines.push('');

  if (upstreamRes.warnings.length || cveRes.warnings.length) {
    lines.push('## Feed warnings');
    for (const w of [...upstreamRes.warnings, ...cveRes.warnings]) lines.push(`- ${w}`);
    lines.push('');
  }

  // RED
  const redMaintained = cveRes.red.filter(r => r.origin !== 'base');
  const redBase = cveRes.red.filter(r => r.origin === 'base');
  lines.push('## Red — act now');
  lines.push('');
  if (upstreamRes.red.length === 0 && redMaintained.length === 0) {
    lines.push('_No urgent items in our maintained (`sources.manifest`) components._');
    lines.push('');
  }
  if (upstreamRes.red.length) {
    lines.push('### Urgent upstream releases / EOL');
    lines.push('');
    lines.push('| Component | Installed | Latest | Lane | Detail |');
    lines.push('|---|---|---|---|---|');
    for (const r of upstreamRes.red) {
      lines.push(`| ${r.pkg} | \`${r.installed}\` | \`${r.latest}\` | ${r.lane} | ${r.detail} |`);
    }
    lines.push('');
  }
  if (redMaintained.length) {
    lines.push('### Maintained packages (`sources.manifest`) with CVEs');
    lines.push('');
    lines.push('| Package | Installed | Origin | KEV | High | CVEs | Fixed >= | Sample CVEs |');
    lines.push('|---|---|---|---:|---:|---:|---|---|');
    for (const r of redMaintained) {
      lines.push(`| **${r.program}** | \`${r.installed}\` | \`${r.origin}\` | ${r.kev} | ${r.high} | ${r.std} | \`${r.fixed}\` | ${r.sample} |`);
    }
    lines.push('');
  }
  if (redBase.length) {
    lines.push(`### Stock 2020 base backlog (${redBase.length} packages — tracked for P5 base refresh)`);
    lines.push('');
    lines.push('| Package | Installed | KEV | High | CVEs | Fixed >= | Sample CVEs |');
    lines.push('|---|---|---:|---:|---:|---|---|');
    for (const r of redBase) {
      lines.push(`| **${r.program}** | \`${r.installed}\` | ${r.kev} | ${r.high} | ${r.std} | \`${r.fixed}\` | ${r.sample} |`);
    }
    lines.push('');
  }

  // YELLOW
  lines.push('## Yellow — next release');
  lines.push('');
  if (totalYellow === 0) {
    lines.push('_None._');
    lines.push('');
  } else {
    if (upstreamRes.yellow.length) {
      lines.push('### Newer upstream releases (manifest components)');
      lines.push('');
      lines.push('| Component | Installed | Latest | Lane | Detail |');
      lines.push('|---|---|---|---|---|');
      for (const y of upstreamRes.yellow) {
        lines.push(`| ${y.pkg} | \`${y.installed}\` | \`${y.latest}\` | ${y.lane} | ${y.detail} |`);
      }
      lines.push('');
    }
    if (cveRes.yellow.length) {
      lines.push(`### Non-tier-1 tracked packages with CVEs (${cveRes.yellow.length} — P5 backlog)`);
      lines.push('');
      lines.push('| Package | Installed | Origin | High | CVEs | Fixed >= | Sample CVEs |');
      lines.push('|---|---|---|---:|---:|---|---|');
      for (const y of cveRes.yellow) {
        lines.push(`| ${y.program} | \`${y.installed}\` | \`${y.origin}\` | ${y.high} | ${y.std} | \`${y.fixed}\` | ${y.sample} |`);
      }
      lines.push('');
    }
  }

  // UP-TO-DATE + GREY
  lines.push('## Up to date (tracked feeds)');
  lines.push('');
  for (const s of upstreamRes.ok) lines.push(`- ${s}`);
  lines.push('');

  lines.push(`## Grey — low / ignored (${cveRes.grey.length})`);
  lines.push('');
  if (cveRes.grey.length === 0) {
    lines.push('_None._');
  } else {
    lines.push(cveRes.grey.map(g => `- ${g}`).join('\n'));
  }
  lines.push('');
  lines.push('> Note: Kernel CVEs are tracked via the 6.12 LTS point-release stream rather than raw Debian kernel CVE counts, because 90%+ of kernel CVEs concern drivers disabled in our kernel `.config`.');
  lines.push('');

  return { markdown: lines.join('\n'), totalRed, totalYellow };
}

async function main() {
  const opts = parseArgs(process.argv.slice(2));
  const rules = JSON.parse(fs.readFileSync(RULES_PATH, 'utf8'));
  const manifest = readManifest();
  const inventory = readInventory();

  const dateStr = new Date().toISOString().slice(0, 10);
  fs.mkdirSync(WATCH_DIR, { recursive: true });
  const outPath = opts.out ? path.resolve(opts.out) : path.join(WATCH_DIR, `${dateStr}.md`);

  const [upstreamRes, cveRes] = await Promise.all([
    checkUpstreams(manifest, rules),
    checkCves(inventory, rules, opts),
  ]);

  const { markdown, totalRed, totalYellow } = buildMarkdown(dateStr, upstreamRes, cveRes, manifest, inventory);
  fs.writeFileSync(outPath, markdown, 'utf8');

  if (opts.json) {
    const jsonPath = outPath.replace(/\.md$/i, '.json');
    fs.writeFileSync(jsonPath, JSON.stringify({ date: dateStr, totalRed, totalYellow, upstream: upstreamRes, cves: cveRes }, null, 2), 'utf8');
  }

  console.log(`watch-upstream: wrote ${outPath} (${totalRed} red, ${totalYellow} yellow, ${cveRes.grey.length} grey)`);

  if (opts.notify && totalRed > 0) {
    sendWindowsNotification(totalRed, totalYellow, outPath);
  }

  if (opts.exitOnRed && totalRed > 0) process.exit(2);
}

main().catch(err => {
  console.error('watch-upstream: FATAL:', err);
  process.exit(1);
});
