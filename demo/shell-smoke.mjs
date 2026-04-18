// demo/shell-smoke.mjs
//
// End-to-end browser smoke for the photo-ai-lisp /shell and /term pages,
// targeting the ghostty-web frontend (WASM VT parser, canvas renderer).
//
// Proves the full byte-pipe works:
//   - ES module /static/ghostty-web/ghostty-web.js imports, init() resolves
//   - new Terminal(...) mounts a <canvas> in #terminal
//   - WebSocket connects (status div flips to "connected")
//   - Keystrokes typed through page.keyboard reach the WebSocket (binary
//     frames via TextEncoder on the page, decoded back to cmd.exe stdin)
//   - Bytes flowing back render into ghostty-web's grid — asserted by
//     walking term.buffer.active.getLine(y).translateToString() for all
//     visible + scrollback rows, since canvas contents cannot be read
//     via innerText
//
// Usage:
//   node demo/shell-smoke.mjs              # assumes server on localhost:18091
//   BASE=http://localhost:PORT node ...    # override base URL
//
// Output artifacts (in demo/):
//   shell-smoke.png, shell-console.log, shell-dom.txt
//   term-smoke.png,  term-console.log,  term-dom.txt
//
// Exit code: 0 on PASS, 1 on FAIL. On failure, *-FAIL.* copies are also left.

import puppeteer from "puppeteer-core";
import { writeFile, copyFile } from "node:fs/promises";
import { existsSync } from "node:fs";

const BASE = process.env.BASE || "http://localhost:18091";

const CHROME_CANDIDATES = [
  "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe",
  "C:\\Program Files (x86)\\Google\\Chrome\\Application\\chrome.exe",
];
const chromePath = CHROME_CANDIDATES.find((p) => existsSync(p));
if (!chromePath) {
  console.error("[FATAL] Chrome not found in known locations");
  process.exit(2);
}

const results = [];

// Read every line in scrollback + active viewport out of ghostty-web's
// buffer API. Ghostty-web exposes IBufferLine.translateToString(trimRight).
async function readTerminalText(page) {
  return page.evaluate(() => {
    const t = window.__ghosttyTerm;
    if (!t) return "[__ghosttyTerm not exposed]";
    const buf = t.buffer && t.buffer.active;
    if (!buf) return "[no active buffer]";
    const lines = [];
    // Ghostty-web buffer.active.length = rows + scrollback.
    const total = buf.length || t.rows || 30;
    for (let y = 0; y < total; y++) {
      const line = buf.getLine(y);
      if (!line) continue;
      try {
        lines.push(line.translateToString(true));
      } catch (e) {
        lines.push(`[line ${y} err: ${e.message}]`);
      }
    }
    return lines.join("\n");
  });
}

async function runCase({ name, path, typeText, expect, pngPath, consolePath, domPath }) {
  console.log(`\n=== ${name}: ${BASE}${path} ===`);
  const browser = await puppeteer.launch({
    executablePath: chromePath,
    headless: "new",
    args: ["--no-sandbox", "--disable-dev-shm-usage"],
    defaultViewport: { width: 1600, height: 700 },
  });
  const page = await browser.newPage();
  const consoleLines = [];
  page.on("console", (msg) => consoleLines.push(`[${msg.type()}] ${msg.text()}`));
  page.on("pageerror", (err) => consoleLines.push(`[pageerror] ${err.message}`));
  page.on("requestfailed", (req) =>
    consoleLines.push(`[reqfail] ${req.url()} ${req.failure()?.errorText}`),
  );

  let pass = false;
  let reason = "";
  let domText = "";

  try {
    await page.goto(`${BASE}${path}`, { waitUntil: "networkidle2", timeout: 20000 });

    // ghostty-web's init() resolves in the page module — wait for the
    // Terminal instance to be exposed on window.
    await page.waitForFunction(() => !!window.__ghosttyTerm, { timeout: 15000 });

    // term.open() appends a <canvas> into #terminal.
    await page.waitForSelector("#terminal canvas", { timeout: 10000 });

    // Wait for WebSocket OPEN — page's #status div flips to "connected".
    await page.waitForFunction(
      () => {
        const el = document.getElementById("status");
        return el && /connected/i.test(el.textContent || "");
      },
      { timeout: 10000 },
    );

    // Ghostty-web Terminal captures keyboard via a focused canvas (or a
    // hidden input; API gives focus() on the Terminal itself).
    await page.evaluate(() => {
      try {
        window.__ghosttyTerm.focus && window.__ghosttyTerm.focus();
      } catch (_) {}
      const c = document.querySelector("#terminal canvas");
      if (c) c.focus && c.focus();
    });
    await page.keyboard.type(typeText, { delay: 30 });
    await page.keyboard.press("Enter");

    // Give the subprocess / echo server time to respond and render.
    await new Promise((r) => setTimeout(r, 2500));

    domText = await readTerminalText(page);

    // Collapse whitespace so visual soft-wrap doesn't defeat the assertion.
    const flattened = domText.replace(/\s+/g, "");
    pass = flattened.includes(expect.replace(/\s+/g, ""));
    if (!pass) reason = `expected substring "${expect}" not found in buffer`;
  } catch (e) {
    reason = `exception: ${e.message}`;
  }

  await page.screenshot({ path: pngPath, fullPage: true });
  await writeFile(consolePath, consoleLines.join("\n") + "\n");
  await writeFile(domPath, domText);

  if (!pass) {
    await copyFile(pngPath, pngPath.replace(/\.png$/, "-FAIL.png"));
    await copyFile(consolePath, consolePath.replace(/\.log$/, "-FAIL.log"));
    await copyFile(domPath, domPath.replace(/\.txt$/, "-FAIL.txt"));
  }

  await browser.close();

  console.log(pass ? `PASS ${name}` : `FAIL ${name}: ${reason}`);
  console.log(`  screenshot: ${pngPath}`);
  console.log(`  console:    ${consolePath}`);
  console.log(`  dom:        ${domPath}`);
  if (!pass) {
    console.log(`--- console (last lines) ---`);
    console.log(consoleLines.slice(-20).join("\n"));
    console.log(`--- buffer (first 1200 chars) ---`);
    console.log(domText.slice(0, 1200));
  }
  results.push({ name, pass, reason });
}

try {
  await runCase({
    name: "term (/term echo)",
    path: "/term",
    typeText: "hello echo",
    expect: "hello echo",
    pngPath: "demo/term-smoke.png",
    consolePath: "demo/term-console.log",
    domPath: "demo/term-dom.txt",
  });

  await runCase({
    name: "shell (/shell cmd.exe)",
    path: "/shell",
    typeText: "echo photo-ai-lisp-smoke-OK",
    expect: "photo-ai-lisp-smoke-OK",
    pngPath: "demo/shell-smoke.png",
    consolePath: "demo/shell-console.log",
    domPath: "demo/shell-dom.txt",
  });
} catch (e) {
  console.error("harness error:", e);
  process.exit(1);
}

const failed = results.filter((r) => !r.pass);
if (failed.length) {
  console.error(`\n${failed.length}/${results.length} cases FAILED`);
  process.exit(1);
}
console.log(`\nAll ${results.length}/${results.length} cases PASSED`);
