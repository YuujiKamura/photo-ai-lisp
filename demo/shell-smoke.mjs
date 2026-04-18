// demo/shell-smoke.mjs
//
// End-to-end browser smoke for the photo-ai-lisp /shell and /term pages.
//
// Proves the full byte-pipe works:
//   - HTML page loads
//   - xterm.js (the Terminal the repo actually vendors in via unpkg) mounts
//   - WebSocket connects (status reflected in terminal)
//   - Keystrokes typed through page.keyboard reach the WebSocket
//   - Bytes flowing back (echo server for /term, cmd.exe for /shell) render in
//     the terminal's DOM text
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
    await page.goto(`${BASE}${path}`, { waitUntil: "networkidle2", timeout: 15000 });

    // xterm.js renders .xterm into #terminal, with internal canvases.
    await page.waitForSelector("#terminal .xterm", { timeout: 10000 });

    // Wait until a Terminal instance has opened: .xterm-screen appears once
    // term.open(...) has laid out the viewport.
    await page.waitForSelector("#terminal .xterm-screen", { timeout: 10000 });

    // Wait for WebSocket OPEN — the page writes a "[connected]" banner.
    await page.waitForFunction(
      () => {
        const el = document.querySelector("#terminal");
        return el && el.innerText.toLowerCase().includes("connected");
      },
      { timeout: 10000 },
    );

    // xterm.js captures keyboard via an internal .xterm-helper-textarea that
    // must have focus. Clicking .xterm or .xterm-screen does not always
    // transfer focus to it under headless Chrome, so we focus it directly.
    await page.$eval("#terminal .xterm-helper-textarea", (el) => el.focus());
    await page.keyboard.type(typeText, { delay: 30 });
    await page.keyboard.press("Enter");

    // Give the subprocess / echo server time to respond and render.
    await new Promise((r) => setTimeout(r, 2500));

    domText = await page.$eval("#terminal", (el) => el.innerText);

    // xterm.js soft-wraps long lines at the viewport width, which shows up in
    // innerText as a newline inside our command. Collapse whitespace so the
    // assertion matches the logical content, not the visual layout.
    const flattened = domText.replace(/\s+/g, "");
    pass = flattened.includes(expect.replace(/\s+/g, ""));
    if (!pass) reason = `expected substring "${expect}" not found in terminal DOM`;
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
    console.log(`--- dom (first 1200 chars) ---`);
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
