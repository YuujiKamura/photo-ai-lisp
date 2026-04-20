# tests/e2e — Puppeteer regression harness

Locks in the `/shell` picker → `claude` REPL full stack (Team E).

## Stack

```
 browser (headless chrome)
       │
       │  xterm-style canvas (ghostty-web)
       ▼
 /shell HTML  ─── WebSocket ───▶  /ws/shell  (hunchentoot + hunchensocket)
                                        │
                                        │  child stdin/stdout
                                        ▼
                               cmd.exe or bash  ──▶  pick-agent  ──▶  claude CLI
                                        │
                                        ▼
                            shell-trace ring  ◀── /api/shell-trace (HTTP GET)
```

Detection is done by polling **`/api/shell-trace`** after typing `1+Enter`.
We do NOT OCR the canvas — the ring is the server's own record of every
byte that crossed the WS, so a trace hit is exactly "the browser saw it".

## Manual run

Prereqs (harness will `SKIP` if any is missing):

- `node` (>= 18, uses top-level `await` and ESM)
- `puppeteer-core` (either in `tests/e2e/node_modules/` or the repo's
  pre-existing `demo/node_modules/`)
- Google Chrome at a known path (or `PAI_E2E_CHROME=/path/to/chrome`)
- `claude` CLI on `PATH`

```bash
# 1. Start the Lisp server (from the repo root).
./scripts/demo.sh &
# ... or pick your own port in a REPL: (photo-ai-lisp:start :port 8092)

# 2. Run the harness.
cd tests/e2e
node picker-to-claude.mjs --port 8090
# stdout : PASS | FAIL <reason> | SKIP <reason>
# stderr : JSON judgement breakdown
```

## From fiveam

`tests/e2e-tests.lisp` defines `picker-to-claude-e2e` inside the
`e2e-suite`. It:

1. Starts `photo-ai-lisp:start` on `$PAI_E2E_PORT` (default: random
   port 9000–9899 picked per-run — demo.sh is intentionally bypassed
   because it hard-codes 8090 and Team E brief forbids editing it).
2. Shells out to `node picker-to-claude.mjs --port N`.
3. Passes if the first stdout line is `PASS`, skips on `SKIP`, fails
   on `FAIL` (stderr is captured into the failure message).
4. Always calls `photo-ai-lisp:stop` in an `unwind-protect`.

## Env overrides

| Var                   | Default                       | Meaning                           |
|-----------------------|-------------------------------|-----------------------------------|
| `PAI_E2E_PORT`        | 8090 (harness) / random (5am) | Server port                       |
| `PAI_E2E_HOST`        | 127.0.0.1                     | Server host                       |
| `PAI_E2E_CHROME`      | auto-detect                   | Chrome executable path            |
| `PAI_E2E_BOOT_WAIT_MS`| 4000                          | ms to wait before typing "1"      |
| `PAI_E2E_REPL_WAIT_MS`| 20000                         | ms to wait for claude signature   |
| `PAI_E2E_MATCHERS`    | `Claude Code\|claude>\|…`     | `\|`-separated substring alts     |
| `PAI_E2E_SKIP`        | unset                         | If `1`, fiveam test auto-SKIPs    |
