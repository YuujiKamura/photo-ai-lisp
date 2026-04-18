# demo — browser smoke for `/shell` and `/term`

End-to-end browser smoke that proves the byte-pipe served by `photo-ai-lisp`
actually works in a real (headless) browser:

* `/term` — xterm.js → WebSocket `/ws/echo` → echo server → back to xterm.js
* `/shell` — xterm.js → WebSocket `/ws/shell` → child `cmd.exe` (on Windows)
  or `/bin/bash --norc --noprofile` → back to xterm.js

## What it proves

For each page:

1. HTML loads and xterm.js mounts (`#terminal .xterm-screen` appears).
2. The WebSocket reaches `OPEN` (the inline script writes a `[connected]`
   / `Connected to echo server` banner).
3. Keystrokes injected via `page.keyboard.type(...)` travel through
   xterm.js' `onData` → `ws.send(...)` and reach the server side.
4. Bytes coming back from the subprocess (`cmd.exe` banner, the `echo`
   command's output, or the echo server replay) are written to the
   `term.write(...)` stream and land in the DOM text of `#terminal`.

For `/shell` we assert that `photo-ai-lisp-smoke-OK` (the output of
`echo photo-ai-lisp-smoke-OK`) appears in the rendered DOM. For `/term` we
assert that `hello echo` appears.

## Artifacts committed alongside this README

* `shell-smoke.png` — headless-Chrome screenshot of `/shell` after the smoke
  command ran. Must show the cmd.exe banner and the echoed output.
* `term-smoke.png`  — same for `/term`.
* `shell-smoke.mjs` — the reproducible smoke driver (Node + puppeteer-core).

The transient logs (`shell-console.log`, `shell-dom.txt`, and their `/term`
siblings) are regenerated on every run and are checked in as a reference of
the last-known-good output.

## How to run

### Prereqs

* Node.js 20+ (we used 22.17).
* Google Chrome installed at one of:
  `C:\Program Files\Google\Chrome\Application\chrome.exe`
  `C:\Program Files (x86)\Google\Chrome\Application\chrome.exe`
* `puppeteer-core` (installed via `npm install` in this directory).

### Start the server

From the repo root (this worktree):

```bash
# Nuke any stale FASL for this worktree so code edits actually take effect.
find "$LOCALAPPDATA/cache/common-lisp/sbcl-2.6.3-win-x64" \
    -type f -path "*$(basename "$PWD")*" -delete 2>/dev/null || true

# Start on an unused port in the 1809x range.
sbcl --non-interactive \
  --eval "(require 'asdf)" \
  --eval "(pushnew (truename \"./\") asdf:*central-registry* :test #'equal)" \
  --eval "(asdf:clear-configuration)" \
  --eval "(pushnew (truename \"./\") asdf:*central-registry* :test #'equal)" \
  --eval "(asdf:load-system :photo-ai-lisp)" \
  --eval "(photo-ai-lisp:start :port 18091)" \
  --eval "(format t \"~%READY~%\")" \
  --eval "(sleep 300)" \
  --eval "(photo-ai-lisp:stop)" &
```

### Run the smoke

```bash
cd demo
npm install        # puppeteer-core (one-time)
node shell-smoke.mjs
```

Override the base URL with `BASE=http://localhost:PORT node shell-smoke.mjs`
if the server is running somewhere else.

Exit code is `0` on PASS, `1` on FAIL. Failure artifacts are copied to
`*-FAIL.{png,log,txt}` next to the successful ones.

## Known quirks discovered while writing this

These are the real bugs we had to fix on the server side to get a green
smoke:

1. **`src/term.lisp` — stdout pump flushed NIL on Windows.**
   `listen` can return T while `read-char` then returns NIL (e.g. mid-way
   through a UTF-8 sequence on a pipe with OEM codepage output). Pushing
   that NIL into the outgoing character buffer eventually raised
   `NIL is not of type (MOD 1114112)` and killed the pump. Fixed by
   treating a NIL read as "no data right now": flush what we have, sleep
   briefly, loop.

2. **`src/term.lisp` — text-frame keystrokes containing a bare CR killed
   the WebSocket.**
   xterm.js emits `\r` (0x0D) for Enter. When hunchensocket unmasks a
   text frame whose payload ends in a lone CR, flexi-streams' `:crlf`
   line-ending decoder peeks for the LF that isn't there, the UTF-8
   decoder returns NIL for the peeked code, and `code-char NIL` signals
   the same `(MOD 1114112)` error. hunchensocket catches that at
   `read-handle-loop`, closes with 1011 "Internal error", and the browser
   sees `[ws error]` on the first Enter. Fixed by switching the `/shell`
   page to send **binary** frames (`TextEncoder`-encoded bytes) and adding
   a `binary-message-received` / `check-message` method on `shell-resource`
   that accepts them and translates `\r` → `\r\n` on the way into
   `cmd.exe`'s stdin (cmd.exe pipe-reads expect a newline to end a line).

3. **`src/term.lisp` — `cmd.exe /Q`.** Without `/Q`, cmd.exe prints every
   keystroke it receives as if the user typed them on the console. Over
   a pipe that meant the terminal showed `echo photo-ai-lisp-smoke-OK`
   twice. With `/Q` we only see the command's actual output.

See `git log` on this branch for the exact commits.
