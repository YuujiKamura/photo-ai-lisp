#!/usr/bin/env node
// Team E — Puppeteer E2E regression harness for /shell -> picker -> Claude REPL.
//
// Flow this locks in (was only reproducible by hand before):
//   1. Open http://<host>:<port>/shell in headless Chrome.
//   2. Wait for the Lisp server's agent-picker auto-inject banner to land.
//   3. Type "1" + Enter to choose Claude from the picker.
//   4. Wait for the child `claude` CLI to boot and its banner to flow
//      back through /ws/shell into the shell-trace ring.
//   5. Poll /api/shell-trace (JSON) until a Claude REPL signature appears
//      in any :out entry, or the deadline elapses.
//
// We deliberately do NOT try to read the xterm/ghostty-web canvas — the
// renderer is WebGL/2D canvas and has no DOM text. The shell-trace ring
// is the server's own record of every byte that flowed over /ws/shell,
// so detection there is exactly equivalent to "the browser saw this".
//
// Stdout contract (consumed by tests/e2e-tests.lisp):
//   Exactly one of these lines, followed by LF:
//     PASS
//     FAIL <short-reason>
//     SKIP <short-reason>
//
// Stderr: human-readable JSON with the full judgement breakdown.
//
// Exit codes:
//   0  -> PASS
//   1  -> FAIL
//   2  -> SKIP (dependency missing: chrome, puppeteer, claude CLI, etc.)
//   3  -> internal error (bug in the harness itself)

import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';

// ---------- CLI args ----------

function parseArgs(argv) {
  const out = {
    port: Number(process.env.PAI_E2E_PORT) || 8090,
    host: process.env.PAI_E2E_HOST || '127.0.0.1',
    verbose: false,
    bootWaitMs: Number(process.env.PAI_E2E_BOOT_WAIT_MS) || 4000,
    replWaitMs: Number(process.env.PAI_E2E_REPL_WAIT_MS) || 20000,
    traceMatchers: (
      process.env.PAI_E2E_MATCHERS ||
      // Alternation of independent signatures — ANY one hit = PASS.
      // Keep each token short and ASCII so it survives the
      // shell-trace %preview sanitizer (which blanks CR/LF and dots
      // out anything <0x20).
      'Claude Code|claude>|Welcome to Claude|claude --help|Try "help"|/help for help|cwd:'
    ).split('|').map(s => s.trim()).filter(Boolean),
  };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--verbose' || a === '-v') out.verbose = true;
    else if (a === '--port')   out.port = Number(argv[++i]);
    else if (a === '--host')   out.host = argv[++i];
    else if (a === '--boot-wait-ms') out.bootWaitMs = Number(argv[++i]);
    else if (a === '--repl-wait-ms') out.replWaitMs = Number(argv[++i]);
    else if (a === '--matchers') out.traceMatchers = argv[++i].split('|');
  }
  return out;
}

const args = parseArgs(process.argv.slice(2));

function log(...xs)  { if (args.verbose) process.stderr.write(xs.join(' ') + '\n'); }
function warn(...xs) { process.stderr.write(xs.join(' ') + '\n'); }
function emit(line)  { process.stdout.write(line + '\n'); }

function finish(verdict, reason, detail) {
  const payload = {
    verdict,
    reason,
    detail,
    args: { port: args.port, host: args.host,
            bootWaitMs: args.bootWaitMs, replWaitMs: args.replWaitMs,
            traceMatchers: args.traceMatchers },
    ts: new Date().toISOString(),
  };
  warn(JSON.stringify(payload, null, 2));
  if (verdict === 'PASS') { emit('PASS'); process.exit(0); }
  if (verdict === 'SKIP') { emit('SKIP ' + reason); process.exit(2); }
  if (verdict === 'FAIL') { emit('FAIL ' + reason); process.exit(1); }
  emit('FAIL internal'); process.exit(3);
}

// ---------- dependency probes ----------

function whichChromeSync() {
  if (process.env.PAI_E2E_CHROME) return process.env.PAI_E2E_CHROME;
  const candidates = [
    'C:/Program Files/Google/Chrome/Application/chrome.exe',
    'C:/Program Files (x86)/Google/Chrome/Application/chrome.exe',
    process.env.LOCALAPPDATA &&
      path.join(process.env.LOCALAPPDATA, 'Google/Chrome/Application/chrome.exe'),
    '/usr/bin/google-chrome',
    '/usr/bin/chromium',
    '/usr/bin/chromium-browser',
    '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  ].filter(Boolean);
  for (const c of candidates) {
    try { if (fs.statSync(c).isFile()) return c; } catch {}
  }
  return null;
}

async function importPuppeteer() {
  // 1. Prefer a local install under tests/e2e/node_modules.
  // 2. Fall back to the existing demo/node_modules puppeteer-core so we
  //    don't force a re-download on the dev box where it already lives.
  try {
    return (await import('puppeteer-core')).default;
  } catch (e1) {
    log('tests/e2e puppeteer-core not found:', e1.message);
    const demoPath = path.resolve(
      new URL('.', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1'),
      '../../demo/node_modules/puppeteer-core/lib/esm/puppeteer/puppeteer-core.js'
    );
    try {
      return (await import('file://' + demoPath)).default;
    } catch (e2) {
      log('demo puppeteer-core also missing:', e2.message);
      return null;
    }
  }
}

// ---------- server probes ----------

async function httpGet(url, timeoutMs = 3000) {
  const ctl = new AbortController();
  const t = setTimeout(() => ctl.abort(), timeoutMs);
  try {
    const r = await fetch(url, { signal: ctl.signal });
    const body = await r.text();
    return { ok: r.ok, status: r.status, body };
  } catch (e) {
    return { ok: false, status: 0, body: '', error: String(e) };
  } finally {
    clearTimeout(t);
  }
}

async function serverAlive(host, port) {
  const r = await httpGet(`http://${host}:${port}/`, 2000);
  return r.ok || r.status >= 200;
}

async function waitForServer(host, port, deadlineMs) {
  const end = Date.now() + deadlineMs;
  while (Date.now() < end) {
    if (await serverAlive(host, port)) return true;
    await sleep(200);
  }
  return false;
}

async function fetchTrace(host, port) {
  const r = await httpGet(`http://${host}:${port}/api/shell-trace`, 3000);
  if (!r.ok) return [];
  try { return JSON.parse(r.body); }
  catch { return []; }
}

function traceHits(entries, matchers) {
  const hits = [];
  for (const e of entries) {
    const text = (e && e.preview) || '';
    const dir  = (e && e.dir) || '';
    // :out entries are the ones that came from the child process.
    // :in and :meta are what we sent; matching on those would be a
    // false positive (we'd be detecting our own picker inject, not
    // the actual Claude REPL boot).
    if (dir !== 'out') continue;
    for (const m of matchers) {
      if (text.toLowerCase().includes(m.toLowerCase())) {
        hits.push({ matcher: m, ts: e.ts, preview: text.slice(0, 120) });
        break;
      }
    }
  }
  return hits;
}

function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }

// ---------- main ----------

(async () => {
  // ---- probe: server ----
  if (!await waitForServer(args.host, args.port, 5000)) {
    return finish('SKIP', 'server-not-listening',
                  { url: `http://${args.host}:${args.port}/` });
  }

  // ---- probe: chrome ----
  const chromeExe = whichChromeSync();
  if (!chromeExe) {
    return finish('SKIP', 'chrome-not-found',
                  { hint: 'set PAI_E2E_CHROME=/path/to/chrome' });
  }
  log('chrome:', chromeExe);

  // ---- probe: puppeteer-core ----
  const puppeteer = await importPuppeteer();
  if (!puppeteer) {
    return finish('SKIP', 'puppeteer-core-not-installed',
                  { hint: 'cd tests/e2e && npm install puppeteer-core' });
  }

  // ---- launch ----
  let browser;
  try {
    browser = await puppeteer.launch({
      executablePath: chromeExe,
      headless: 'new',
      defaultViewport: { width: 1280, height: 800 },
      args: ['--no-sandbox', '--disable-dev-shm-usage'],
    });
  } catch (e) {
    return finish('SKIP', 'chrome-launch-failed',
                  { error: String(e).slice(0, 200) });
  }

  const judgement = {
    phases: [],
    firstMatch: null,
    traceSampleCount: 0,
  };

  try {
    const page = await browser.newPage();
    const url = `http://${args.host}:${args.port}/shell`;
    log('goto', url);
    await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 15000 });

    // Let the ghostty-web WASM boot, the WebSocket attach, the server
    // spawn cmd.exe / bash, and the picker auto-inject land. The actual
    // boot time varies with cold Chromium cache vs warm; 4s is usually
    // enough once the first ever run has seeded the profile.
    log('sleep boot', args.bootWaitMs);
    await sleep(args.bootWaitMs);
    judgement.phases.push({ phase: 'boot', ok: true, waitedMs: args.bootWaitMs });

    // Type "1" + Enter to choose Claude from the picker.
    log('type 1 + Enter');
    await page.keyboard.type('1');
    await sleep(120);
    await page.keyboard.press('Enter');
    judgement.phases.push({ phase: 'keystroke', ok: true });

    // Poll /api/shell-trace until we see a Claude REPL signature,
    // or the REPL wait deadline elapses.
    const deadline = Date.now() + args.replWaitMs;
    let lastLen = 0;
    while (Date.now() < deadline) {
      const entries = await fetchTrace(args.host, args.port);
      judgement.traceSampleCount = entries.length;
      if (entries.length !== lastLen) {
        log('trace size', entries.length);
        lastLen = entries.length;
      }
      const hits = traceHits(entries, args.traceMatchers);
      if (hits.length > 0) {
        judgement.firstMatch = hits[0];
        judgement.phases.push({ phase: 'detect', ok: true, hitCount: hits.length });
        // Screenshot on success too — gives CI a visual receipt.
        try {
          const shotDir = path.resolve(new URL('.', import.meta.url).pathname
            .replace(/^\/([A-Za-z]:)/, '$1'), '../../.dispatch');
          if (!fs.existsSync(shotDir)) fs.mkdirSync(shotDir, { recursive: true });
          await page.screenshot({ path: path.join(shotDir, 'team-e-e2e-pass.png') });
        } catch (e) { log('screenshot fail:', e.message); }
        return finish('PASS', 'claude-repl-signature-detected', judgement);
      }
      await sleep(500);
    }

    // Nothing matched — capture diagnostics.
    const finalTrace = await fetchTrace(args.host, args.port);
    const outPreviews = finalTrace
      .filter(e => e && e.dir === 'out')
      .slice(0, 20)
      .map(e => e.preview);
    judgement.phases.push({ phase: 'detect', ok: false });
    judgement.outPreviewsSample = outPreviews;
    try {
      const shotDir = path.resolve(new URL('.', import.meta.url).pathname
        .replace(/^\/([A-Za-z]:)/, '$1'), '../../.dispatch');
      if (!fs.existsSync(shotDir)) fs.mkdirSync(shotDir, { recursive: true });
      await page.screenshot({ path: path.join(shotDir, 'team-e-e2e-fail.png') });
    } catch (e) { log('screenshot fail:', e.message); }
    return finish('FAIL', 'no-claude-signature-in-trace', judgement);

  } catch (e) {
    return finish('FAIL', 'harness-exception', { error: String(e).slice(0, 500) });
  } finally {
    try { await browser.close(); } catch {}
  }
})().catch(e => {
  warn(String(e && e.stack || e));
  emit('FAIL harness-crash');
  process.exit(3);
});
