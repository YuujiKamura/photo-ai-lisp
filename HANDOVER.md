# Handover — 2026-04-18 evening

This file is the starting point for the next session. Read `LESSONS.md`
first, then this one.

## Current state

- `main` is past the skeleton; Steps A, B, and C are landed.
  - `docs/skill-cli.md` — real probed CLI shape for each photo-* skill
  - `.github/workflows/test.yml` — CI restored
  - `src/agent.lisp` — minimal agent subprocess (`claude -p` one-shot model)
  - `tests/agent-scenario.lisp` — scenario test that spawns real `claude`
- `archive/2026-04-18-drift-snapshot` holds the earlier drift-era code
  for reference.

## Target direction (revised)

Port ghostty-web to Common Lisp. The terminal emulator itself becomes
a Lisp codebase, not a Go binary we shell out to. The point is to
actually use Lisp for the hard parts instead of gluing two ecosystems
together.

```
Browser
  └─ xterm.js (kept for glyph rendering only)
        ↕ WebSocket (hunchensocket)
   photo-ai-lisp (Hunchentoot + Lisp terminal emulator)
        ↕ PTY (ConPTY on Windows via CFFI, pty on Unix)
    child process (bash / cmd / claude / …)
```

The Lisp side owns:

- WebSocket endpoint and message protocol
- PTY spawn/resize/kill
- ANSI / VT100 / ECMA-48 escape-sequence parser
- Screen buffer (grid of cells, cursor, attributes, scrollback)
- CP (Control Plane) protocol for external tools to inject input
  and observe output programmatically

xterm.js stays on the browser side only as the glyph / input
surface. Everything else moves into Lisp.

Reference source: `C:\Users\yuuji\ghostty-web\` (Go implementation,
existing CP protocol). Read it for protocol shape, do not shell it
out.

## Do-next, in order

Each phase ends with a committed, pushed change on `main`. No
subsequent phase starts until the previous one is green and a
screenshot or log proves the stated behavior.

### Phase 1 — WebSocket echo loop

- Add `hunchensocket` to `photo-ai-lisp.asd` depends-on.
- Serve a page at `/term` with xterm.js linked from a CDN.
- Open a WebSocket from the page to `/ws/echo`.
- Every byte the browser sends over the socket, echo back verbatim.
- User types `hello` in xterm, sees `hello` appear (echoed).
- No subprocess, no PTY, no ANSI parsing — just prove the socket
  plumbing works.

Commit: `feat(term): phase 1 — websocket echo through xterm.js`.

### Phase 2 — Pipe subprocess stdio through the socket

- When a client connects to `/ws/shell`, Lisp spawns a subprocess
  (default `cmd.exe` on Windows, `/bin/bash` on Unix) via
  `uiop:launch-program` with plain stdin/stdout pipes — **not a PTY
  yet**.
- Forward WebSocket → process stdin, process stdout → WebSocket.
- Expect broken interactivity (no TTY). That is fine; the point of
  this phase is to prove bidirectional piping works before tackling
  PTY.

Commit: `feat(term): phase 2 — subprocess stdio over websocket`.

### Phase 3 — Real PTY

- Write a `src/pty.lisp` module that opens a pseudo-terminal.
  - On Windows: CFFI bindings to ConPTY (`CreatePseudoConsole`,
    `ResizePseudoConsole`, `ClosePseudoConsole`, overlapped IO).
  - On Unix: `cl-pty` or direct `forkpty` CFFI wrapper.
- Replace Phase 2 plumbing with PTY reads/writes.
- Support resize: WebSocket `resize` message → `ResizePseudoConsole`
  (or `TIOCSWINSZ`).
- Run `bash` / `cmd` interactively in the browser. Curses apps
  (for example `htop` where available, or `vim`) should render at
  least cursor movement correctly even without the ANSI parser,
  because xterm.js parses the escape sequences.

Commit: `feat(term): phase 3 — PTY backend`.

### Phase 4 — In-Lisp ANSI parser

- Add `src/ansi.lisp` that implements an ECMA-48 / VT100 parser
  state machine.
- Start narrow: CSI sequences for cursor move, SGR for colors and
  attributes, and basic OSC. Skip DCS and exotic modes initially.
- The parser emits events (`:print CHAR`, `:cursor-move ROW COL`,
  `:set-attr ...`, `:erase ...`) that a consumer can translate into
  screen updates.
- Unit-test the parser against a small corpus of known sequences —
  this is pure data, safe to unit-test.

Commit: `feat(term): phase 4 — ANSI parser in Lisp`.

### Phase 5 — Screen buffer model

- `src/screen.lisp`: grid of cells, cursor, scrollback ring, line
  wrap, tab stops. Apply parser events to mutate the screen.
- Snapshot API: `(screen->text)` and `(screen->html)` for debugging
  and for the CP protocol to query state without a browser.

Commit: `feat(term): phase 5 — screen buffer with scrollback`.

### Phase 6 — CP protocol

- WebSocket message types for external (non-browser) clients:
  - `input TEXT` — push keystrokes as if typed.
  - `snapshot` — request current screen state, reply JSON.
  - `run COMMAND` — convenience: send command + newline + wait for
    prompt signal.
  - `resize COLS ROWS`, `kill`, `spawn`.
- Lisp-side API: `(cp-send-input session text)`,
  `(cp-snapshot session)`, etc. The agent subprocess from Step C can
  now drive the same terminal a human is watching.

Commit: `feat(term): phase 6 — CP protocol for external clients`.

### Phase 7 — Wire the agent through the terminal

- `claude -p` is still stdin/stdout, but now its stdout can be piped
  into a CP session so the browser sees it render through the full
  stack.
- Photo-oriented skill wrappers (originally Steps E/F) come back as
  tool calls the agent makes; their stdout shows up in the terminal
  too.

Commit: `feat(agent): run claude through the Lisp terminal`.

## Deferred until after Phase 7

- `src/skills.lisp` typed wrappers (was Step E). Blocked on the
  terminal being real; otherwise the wrappers can be built but not
  observed.
- Agent tool bridge with JSON schemas (was Step F).
- Landing page / README rewrites to describe the terminal emulator.
- Public hosting of any kind. This emulator will spawn arbitrary
  processes; it stays localhost-only forever unless an authz layer
  is built first.

## Non-goals for this pass

- Re-implementing ghostty-web's Go frontend server as a Go-to-Lisp
  transpilation. Read its design, then write idiomatic Common Lisp.
- Full VT220 / VT520 emulation. Aim for a subset that covers
  `bash`, `cmd`, `claude`, and curses-light programs.
- Performance tuning before correctness. 60 FPS is not a goal;
  `htop` at 4 FPS is fine for Phase 3.
- True mouse support, bracketed paste, Sixel graphics. Deferred
  indefinitely.
- A second terminal emulator implementation in the archive branch.
  If it turns out the Lisp emulator is too large, fall back to the
  "pure Lisp chat UI" option discussed in the conversation and
  record that decision here — do not silently depend on ghostty-web
  again.

## Operating constraints

- Do not start Phase N before Phase N-1 is committed, pushed, and
  CI is green.
- Do not add a feature without an observable demonstration — a
  screenshot, a curl trace, or a test log that proves it.
- Do not invent API surface from imagination. Read ghostty-web's
  source for reference shapes, then decide what Lisp-idiomatic
  version you want.
- Do not let AI executors invent CFFI signatures. ConPTY in
  particular has subtle overlapped-IO requirements; consult
  Microsoft's official docs and real working examples before
  writing the binding.
- If stuck more than 20 minutes on a single phase, stop and
  append what is unknown to this file before doing anything else.
- One Claude session does the work top to bottom. No dispatcher
  chains.

## Environment reminders

- SBCL at `C:/Users/yuuji/SBCLLocal/PFiles/Steel Bank Common Lisp/sbcl.exe`
- Quicklisp at `~/quicklisp/`, project symlinked at
  `~/quicklisp/local-projects/photo-ai-lisp/`
- ghostty-web reference source at `C:/Users/yuuji/ghostty-web/`
- ConPTY header: `wincon.h` in the Windows SDK
- Skills at `~/.agents/skills/photo-*/` (parked until Phase 7)
- Windows + Git Bash shell. Use `uiop:os-windows-p` for any
  platform-sensitive branch.

Good luck.
