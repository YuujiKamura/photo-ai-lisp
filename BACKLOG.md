# Backlog — bottom-up atomic tasks

Phases 1 and 4 have landed. Everything else is now broken into
1–3 hour atomic tasks so that multiple agents can grab independent
pieces and land them in parallel.

Each task has:
- **ID** (stable, referenced in commit messages)
- **Deps** (which task IDs must be green first; `-` = none)
- **Branch** (where work lands)
- **Done** checkbox

Legend:
- `[ ]` not started
- `[~]` in progress
- `[x]` committed + pushed + CI green

---

## Track A — Transport & PTY (branch `main` and feature branches off main)

### Phase 2: subprocess stdio over websocket

- [x] **2a** spawn child with piped stdio
      Function `src/proc.lisp:spawn-child` → returns an object holding
      `uiop:process-info`, `stdin-stream`, `stdout-stream`, `stderr-stream`.
      Windows: default command `("cmd.exe")`. Unix: `("/bin/bash")`.
      Deps: `-` · Branch: `main`

- [ ] **2b** pass text from websocket to child stdin
      Extend `src/term.lisp` with a new resource `/ws/shell`.
      Each incoming text message → `write-string` to the live child's stdin + flush.
      One child per connection; lifetime tied to the websocket.
      Deps: `2a` · Branch: `main`

- [ ] **2c** stream child stdout to websocket
      Background thread per session that reads chunks from `stdout-stream`
      and pushes them as websocket text messages.
      Use `bordeaux-threads:make-thread`. Kill thread on disconnect.
      Deps: `2a`, `2b` · Branch: `main`

- [ ] **2d** graceful shutdown
      On websocket close: `close` stdin, wait up to 2s on the process,
      then `uiop:terminate-process`. Join the stdout thread. No leaks.
      Deps: `2c` · Branch: `main`

- [ ] **2e** scenario test: echo round-trip through bash
      `tests/shell-scenario.lisp`. Spawn bash via `/ws/shell`, write
      `echo hi`+LF, read bytes, assert `hi` present. Skip on Windows
      where only `cmd.exe` is guaranteed.
      Deps: `2d` · Branch: `main`

### Phase 3: real PTY

- [ ] **3a** ConPTY CFFI bindings (Windows)
      `src/pty-windows.lisp`. CFFI defcfun for:
      - `CreatePseudoConsole(COORD size, HANDLE hInput, HANDLE hOutput, DWORD dwFlags, HPCON *phPC)`
      - `ResizePseudoConsole(HPCON hPC, COORD size)`
      - `ClosePseudoConsole(HPCON hPC)`
      Plus `CreatePipe` / `CloseHandle` helpers.
      Reference Microsoft docs + pywinpty source (do not invent signatures).
      Deps: `-` · Branch: `feat/3a-conpty`

- [ ] **3b** Unix PTY via forkpty
      `src/pty-unix.lisp`. CFFI binding to `forkpty` or `posix_openpt`.
      Deps: `-` · Branch: `feat/3b-unix-pty`

- [ ] **3c** platform-dispatching PTY API
      `src/pty.lisp` exports `(pty-spawn command args &key rows cols)`,
      `(pty-resize handle rows cols)`, `(pty-kill handle)`.
      Dispatches via `#+windows` / `#+unix` or `(uiop:os-windows-p)`.
      Deps: `3a`, `3b` · Branch: `main` (merge target)

- [ ] **3d** replace phase-2 pipes with PTY
      Modify `/ws/shell` to use `pty-spawn` instead of `spawn-child`.
      Child now sees a TTY; `isatty(0)` is true; colors appear.
      Deps: `3c`, `2d` · Branch: `main`

- [ ] **3e** resize message
      New websocket text message shape: `{"type":"resize","rows":R,"cols":C}`.
      Browser sends on `xterm.onResize`; server calls `pty-resize`.
      Deps: `3d` · Branch: `main`

- [ ] **3f** scenario test: vim renders in the browser PTY
      `tests/pty-scenario.lisp`. Start PTY with vim, send `:q!` + CR,
      assert vim prologue byte pattern appears in the output stream.
      Skip if vim is not on PATH.
      Deps: `3e` · Branch: `main`

---

## Track B — Emulation core (branch `track-b/*`)

### Phase 4: ANSI parser — DONE (commit f62d34f)

- [x] **4a** parser state machine + 38 assertions

### Phase 5: screen buffer

- [ ] **5a** cell + attrs
      `src/screen.lisp`. `defstruct cell (char #\space) (fg 7) (bg 0) (bold nil) (underline nil)`.
      Unit tests for copy, compare, default values.
      Deps: `-` · Branch: `track-b/5a-cell`

- [ ] **5b** grid structure
      `defclass screen (rows cols buffer cursor)`. `buffer` is `(array cell (rows cols))`.
      Constructor `(make-screen rows cols)` fills with default cells.
      Deps: `5a` · Branch: `track-b/5b-grid`

- [ ] **5c** cursor model
      `defstruct cursor (row 0) (col 0) (visible t) (attrs (make-instance 'cell))`.
      Movement helpers `(cursor-move cursor :rel-row dr :rel-col dc)` with
      clamping to grid bounds.
      Deps: `5b` · Branch: `track-b/5c-cursor`

- [ ] **5d** scrollback ring
      When cursor LF past the bottom, push top row into a scrollback deque
      (cap at e.g. 1000 rows). Exposed as `(screen-scrollback screen)`.
      Deps: `5c` · Branch: `track-b/5d-scrollback`

- [ ] **5e.1** apply `:print`
      `(apply-event screen event)` for `(:type :print :char C)`:
      write cell at cursor, advance col, wrap + LF on col == cols.
      Deps: `5c` · Branch: `track-b/5e1-print`

- [ ] **5e.2** apply `:cursor-move`, `:cursor-position`
      Relative and absolute cursor motion.
      Deps: `5e.1` · Branch: `track-b/5e2-cursor`

- [ ] **5e.3** apply `:erase-display`, `:erase-line`
      Modes 0/1/2 per spec.
      Deps: `5e.2` · Branch: `track-b/5e3-erase`

- [ ] **5e.4** apply `:set-attr` (SGR)
      Parse the `:attrs` param list:
      - `0` reset
      - `1` bold, `4` underline, `7` reverse, `22/24/27` their resets
      - `30-37` fg, `40-47` bg, `90-97` bright-fg, `100-107` bright-bg
      - `38;5;n` 256-color fg, `48;5;n` 256-color bg
      - `39`, `49` default fg/bg
      Update cursor-attrs; applied to subsequent prints.
      Deps: `5e.1` · Branch: `track-b/5e4-sgr`

- [ ] **5e.5** apply `:bs`, `:cr`, `:lf`, `:ht`
      Cursor navigation for simple controls. `:lf` at bottom scrolls.
      Deps: `5e.1`, `5d` · Branch: `track-b/5e5-controls`

- [ ] **5f** snapshot to plain text
      `(screen->text screen)` returns a newline-joined string,
      trailing whitespace trimmed per line.
      Deps: `5e.1`-`5e.5` · Branch: `track-b/5f-text`

- [ ] **5g** snapshot to HTML
      `(screen->html screen)` wraps runs of same-attr cells in
      `<span style="...">` tags. Suitable for rendering the current
      state without ANSI processing client-side.
      Deps: `5f` · Branch: `track-b/5g-html`

- [ ] **5h** integration scenario: feed a recorded session
      `tests/screen-scenario.lisp`. Load a fixture byte stream
      (e.g. captured `ls --color` output), feed through parser +
      screen, assert `(screen->text)` matches expected.
      Deps: `5f` · Branch: `track-b/5h-integration`

---

## Merge step — sync tracks

- [ ] **M1** merge `track-b/ansi-parser` (and descendants) into `main`
      Do this after `3c` and `5h` are green. Resolve any ASDF component
      ordering conflicts.
      Deps: `3c`, `5h` · Branch: `main`

---

## Track C — CP protocol (branch off `main` after M1)

### Phase 6: CP protocol

- [ ] **6a** message schema
      `docs/cp-protocol.md` describing the wire format. JSON lines.
      Types: `input`, `snapshot`, `run`, `resize`, `kill`, `spawn`.
      Deps: `M1` · Branch: `feat/6a-cp-schema`

- [ ] **6b** session registry
      `src/cp-session.lisp`. `(cp-new-session)` returns an ID,
      registers a running PTY + screen. `(cp-find-session id)` lookup.
      `(cp-end-session id)` cleanup.
      Deps: `6a` · Branch: `feat/6b-session`

- [ ] **6c** non-browser websocket endpoint
      `/ws/cp` accepts JSON messages, routes to session, returns JSON replies.
      Deps: `6b` · Branch: `feat/6c-cp-endpoint`

- [ ] **6d** snapshot reply
      `{"type":"snapshot-reply","text":"...","html":"...","rows":R,"cols":C}`.
      Deps: `6c`, `5g` · Branch: `feat/6d-snapshot`

- [ ] **6e** input injection
      `{"type":"input","data":"echo hi\n"}` → PTY stdin write.
      Deps: `6c` · Branch: `feat/6e-input`

- [ ] **6f** external ↔ browser broadcast
      If both a browser and an external client attach to the same session,
      any output chunk goes to both. Tested with two fake clients.
      Deps: `6d`, `6e` · Branch: `feat/6f-broadcast`

---

## Track D — Agent integration (after Phase 6)

### Phase 7: claude on the terminal

- [ ] **7a** spawn `claude -p` as a CP session
      `(agent-spawn-in-cp session-id prompt)` runs claude inside the
      PTY with its stdin wired to session input.
      Deps: `6f` · Branch: `feat/7a-agent-spawn`

- [ ] **7b** tool-call parser
      Detect Anthropic-format tool_use blocks in agent output.
      For claude's text-only `-p` mode, that means parsing the
      serialized tool calls in the stream.
      Deps: `7a` · Branch: `feat/7b-toolcall-parse`

- [ ] **7c** tool dispatcher
      Map tool names → Lisp functions. Start with one pass-through
      tool (`list_photos` or similar trivial one).
      Deps: `7b` · Branch: `feat/7c-tool-dispatch`

- [ ] **7d** tool result back to agent
      After dispatching, write the tool result JSON back to the
      agent's stdin in the format the agent expects.
      Deps: `7c` · Branch: `feat/7d-tool-result`

- [ ] **7e** end-to-end scenario
      Browser open at `/term`, agent writes text, tools fire, screen
      reflects both agent text and tool output. Screenshot committed.
      Deps: `7d` · Branch: `main`

---

## How to grab a task

1. Find the smallest `[ ]` task whose deps are all `[x]`.
2. Check out its branch. Open a feature branch off the indicated base.
3. Implement, test, commit with prefix `feat(<id>):` or `chore(<id>):`.
4. Push, open PR (or just push to the feature branch — we are not
   using PR review here), wait for CI green.
5. Mark `[~]` while in progress, `[x]` once merged to the target
   branch. Edit this file as part of the same commit.
6. If stuck > 20 minutes on a single task, stop and append the
   unknown to the task entry, pick a different task.

## Agent allocation hint

- **Claude Sonnet** (current `ghostty-37928`): good at `2a-2e`, `3c-3f`,
  and any integration task. Hands off for `3a`/`3b` (CFFI signatures
  are too easy to hallucinate).
- **Gemini** (current `ghostty-39252`): good at `5a-5h` (pure data,
  spec-driven), `6a-6b` (wire format design), tests. Not for `3a`/`3b`.
- **Main Claude** (orchestrator): owns `3a`/`3b` directly, or delegates
  to a human + Microsoft docs session. Do not task an LLM with ConPTY
  signatures unsupervised.
- **Codex** (if quota recovers): equally good as Claude Sonnet on
  most tasks.

Parallel candidates right now (all `[ ]` with ≥1 dep unblocked):

- `2a` (ready; start of Track A Phase 2)
- `5a` (ready; start of Phase 5 on Track B)
- `6a` (ready once M1, not yet)

Pick one per agent. Do not double-assign.
