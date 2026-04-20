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

- [x] **2b** pass text from websocket to child stdin
      Extend `src/term.lisp` with a new resource `/ws/shell`.
      Each incoming text message → `write-string` to the live child's stdin + flush.
      One child per connection; lifetime tied to the websocket.
      Deps: `2a` · Branch: `main`

- [x] **2c** stream child stdout to websocket
      Background thread per session that reads chunks from `stdout-stream`
      and pushes them as websocket text messages.
      Use `bordeaux-threads:make-thread`. Kill thread on disconnect.
      Deps: `2a`, `2b` · Branch: `main`

- [x] **2d** graceful shutdown
      On websocket close: `close` stdin, wait up to 2s on the process,
      then `uiop:terminate-process`. Join the stdout thread. No leaks.
      Deps: `2c` · Branch: `main`

- [x] **2e** scenario test: echo round-trip through bash
      `tests/shell-scenario.lisp`. Spawn bash via `/ws/shell`, write
      `echo hi`+LF, read bytes, assert `hi` present. Skip on Windows
      where only `cmd.exe` is guaranteed.
      Deps: `2d` · Branch: `main`

### Phase 3: real PTY (broken into parallel atoms)

#### Phase 3 research (docs only, parallel-safe)

- [ ] **3r.1** research Microsoft ConPTY API surface
      `docs/conpty-api.md`. Document every function signature from
      `consoleapi.h` + `processthreadsapi.h` relevant to pseudo-consoles:
      `CreatePseudoConsole`, `ResizePseudoConsole`, `ClosePseudoConsole`,
      `CreatePipe`, `CloseHandle`, `STARTUPINFOEX`, `PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE_HANDLE`.
      No Lisp code. Pure documentation grep from Microsoft docs.
      Deps: `-` · Branch: `docs/3r1-conpty-api`

- [ ] **3r.2** research existing ConPTY wrappers for reference
      `docs/conpty-wrappers.md`. Summarize how pywinpty / node-pty /
      microsoft/Terminal handle the overlapped IO pump, the attribute
      list setup, and the handle cleanup order.
      Deps: `-` · Branch: `docs/3r2-conpty-wrappers`

- [ ] **3r.3** research ghostty-web's Go CP implementation
      `docs/ghostty-web-cp.md`. Read `C:\Users\yuuji\ghostty-web\`,
      extract the CP wire format and the ConPTY glue. Record what we
      can steal verbatim vs what must be re-designed for Lisp.
      Deps: `-` · Branch: `docs/3r3-ghostty-web-cp`

- [ ] **3r.4** research CFFI type helpers for Windows HANDLE / DWORD
      `docs/cffi-windows-types.md`. Document how cffi-grovel or
      manual `defctype` maps `HANDLE`, `DWORD`, `COORD`, `HPCON`, etc.
      Reference cl-async + existing Lisp Windows bindings if found.
      Deps: `-` · Branch: `docs/3r4-cffi-types`

#### Phase 3 implementation (depends on research)

- [ ] **3a.1** CFFI type defs (`COORD`, `HPCON`, `HANDLE`)
      `src/pty-windows-types.lisp`. Just the `defctype` + `defcstruct`.
      No function bindings yet, no behavior. Easy to unit-test by
      round-tripping values through CFFI.
      Deps: `3r.1`, `3r.4` · Branch: `feat/3a1-conpty-types`

- [ ] **3a.2** `CreatePipe` + `CloseHandle` bindings
      `src/pty-windows-pipes.lisp`. Smoke test: create pipe, write
      byte, read byte, close. No pseudo-console yet.
      Deps: `3a.1` · Branch: `feat/3a2-conpty-pipes`

- [ ] **3a.3** `CreatePseudoConsole` + `ClosePseudoConsole`
      `src/pty-windows-core.lisp`. Smoke test: create, then close.
      Do NOT spawn a child process yet.
      Deps: `3a.2`, `3r.2` · Branch: `feat/3a3-conpty-core`

- [ ] **3a.4** `ResizePseudoConsole`
      Same file. Smoke test: call with new COORD, verify no error.
      Deps: `3a.3` · Branch: `feat/3a4-conpty-resize`

- [ ] **3a.5** `STARTUPINFOEX` + attribute list for child spawn
      `src/pty-windows-spawn.lisp`. `InitializeProcThreadAttributeList`,
      `UpdateProcThreadAttribute`, then `CreateProcess` with the pseudo-console.
      Scenario test: spawn `cmd /c echo hi`, read output.
      Deps: `3a.4`, `3r.2` · Branch: `feat/3a5-conpty-spawn`

- [ ] **3b.1** Unix `posix_openpt` + `grantpt` + `unlockpt`
      `src/pty-unix-openpt.lisp`. Just open the PTY, no child yet.
      Deps: `-` · Branch: `feat/3b1-openpt`

- [ ] **3b.2** Unix `fork` + `exec` with slave side
      `src/pty-unix-spawn.lisp`. Or use `forkpty` if available.
      Scenario test: spawn `/bin/echo hi`, read.
      Deps: `3b.1` · Branch: `feat/3b2-fork`

- [ ] **3c** platform-dispatching PTY API
      `src/pty.lisp` re-exports `(pty-spawn ...)`, `(pty-resize ...)`,
      `(pty-kill ...)`. Uses `#+windows` / `#-windows` to pick.
      Deps: `3a.5`, `3b.2` · Branch: `main` (merge target)

- [ ] **3d** replace phase-2 pipes with PTY
      `src/term.lisp` `/ws/shell` swaps in `pty-spawn`.
      Deps: `3c`, `2d` · Branch: `main`

- [ ] **3e** resize websocket message
      Browser sends `{"type":"resize","rows":R,"cols":C}` on
      `xterm.onResize`; server dispatches to `pty-resize`.
      Deps: `3d` · Branch: `main`

- [ ] **3f** scenario: vim renders
      `tests/pty-scenario.lisp`. Skip if vim unavailable.
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

#### Apply-event handlers (all share `5c` as dep; parallelizable once `5c` is green)

- [ ] **5e.1** dispatcher skeleton + `:print`
      `(apply-event screen event)` generic dispatch table.
      `:print` branch: write cell at cursor, advance col, wrap.
      Exposes dispatcher so later 5e.* can attach new handlers.
      Deps: `5c` · Branch: `track-b/5e1-print`

- [ ] **5e.2** `:cursor-move` + `:cursor-position`
      Adds handlers to the dispatcher for relative + absolute cursor.
      Does not depend on `5e.1`'s `:print` semantics.
      Deps: `5e.1` (dispatcher only) · Branch: `track-b/5e2-cursor`

- [ ] **5e.3** `:erase-display` + `:erase-line`
      Modes 0/1/2. Fills cells with default `cell`.
      Deps: `5e.1` (dispatcher only) · Branch: `track-b/5e3-erase`

- [ ] **5e.4a** SGR param stream parser (pure)
      `(parse-sgr-params list)` → plist like `(:reset t)` or
      `(:fg 3 :bold t)`. Pure function, no screen. Split from the
      apply step so it is fully unit-testable against the ECMA-48 spec
      without touching screen state.
      Deps: `-` · Branch: `track-b/5e4a-sgr-parse`

- [ ] **5e.4b** apply parsed SGR to cursor attrs
      Consumes output of `5e.4a`, mutates cursor's default cell attrs.
      Deps: `5e.4a`, `5e.1` · Branch: `track-b/5e4b-sgr-apply`

- [ ] **5e.5** `:bs`, `:cr`, `:lf`, `:ht`
      Simple controls. `:lf` at bottom scrolls (requires `5d`).
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

#### Phase 6 research (docs only, parallel-safe, no M1 dep)

- [ ] **6r.1** research JSON line framing conventions
      `docs/cp-framing.md`. Survey how other CP/REPL protocols
      (LSP, DAP, ghostty-web, jupyter) frame JSON messages over
      a stream: newline-delimited, length-prefixed, or envelope-wrapped.
      Recommend one approach with rationale.
      No Lisp code. Pure docs.
      Deps: `-` · Branch: `docs/6r1-framing`

- [ ] **6r.2** survey cl-json / jsown / shasht / com.gigamonkeys.json
      `docs/cp-json-lib.md`. Load each in SBCL, compare API surface
      for encode-to-string + decode-from-string, streaming parse
      availability, and maintenance status. Pick one for cp-json.lisp.
      No Lisp code beyond REPL exploration.
      Deps: `-` · Branch: `docs/6r2-json-lib`

#### Phase 6 pure data (parallel-safe after 6r.*)

- [ ] **6a.1** message schema docs
      `docs/cp-protocol.md`. Wire format spec: JSON lines (or chosen
      framing from 6r.1). Document every message type with example
      payloads: `spawn`, `input`, `snapshot`, `resize`, `kill`,
      `snapshot-reply`, `output`, `error`.
      No code.
      Deps: `6r.1` · Branch: `feat/6a1-cp-schema`

- [ ] **6a.2** JSON encode/decode helpers (pure)
      `src/cp-json.lisp`. `(cp-encode plist)` → JSON string,
      `(cp-decode string)` → plist. Uses library from 6r.2.
      Unit tests: round-trip all message types from 6a.1.
      No side effects, no WS, no PTY.
      Deps: `6r.2`, `6a.1` · Branch: `feat/6a2-cp-json`

- [ ] **6b.1** session ID generator (pure)
      `(generate-session-id)` → hex string (e.g. 16-char random).
      Pure function, no state. Unit test: uniqueness across 1000 calls.
      Lives in `src/cp-session.lisp` (new file).
      Deps: `-` · Branch: `feat/6b1-session-id`

#### Phase 6 session registry (sequential within 6b.*)

- [ ] **6b.2** session registry — storage only
      `src/cp-session.lisp`. Hash table + `bordeaux-threads:make-lock`.
      `(cp-new-session)` allocates ID, stores empty plist.
      `(cp-find-session id)` lookup, `(cp-end-session id)` delete.
      Unit tests: new → find → end lifecycle; concurrent new from 2 threads.
      No PTY or screen yet.
      Deps: `6b.1` · Branch: `feat/6b2-session-store`

- [ ] **6b.3** session PTY + screen attachment
      Add `:pty` and `:screen` slots to session plist.
      `(cp-session-attach-pty session-id pty)`,
      `(cp-session-attach-screen session-id screen)`.
      Wires up to Phase 3 `pty-spawn` and Phase 5 `make-screen`.
      Unit test: attach fake structs, retrieve via cp-find-session.
      Deps: `6b.2`, `3c`, `5b` · Branch: `feat/6b3-session-attach`

#### Phase 6 WebSocket endpoint (depends on 6b.2 + 6a.2)

- [ ] **6c.1** `/ws/cp` resource skeleton
      `src/cp-endpoint.lisp`. New `cp-client` / `cp-resource` classes.
      `client-connected` → registers new CP session.
      `client-disconnected` → calls `cp-end-session`.
      No message routing yet; logs connect/disconnect.
      Deps: `6b.2` · Branch: `feat/6c1-cp-resource`

- [ ] **6c.2** message dispatcher
      `text-message-received` parses JSON (via 6a.2), dispatches on
      `:type`. Unknown type → `{"type":"error","message":"unknown"}`.
      Handler table: `defvar *cp-handlers* (make-hash-table :test #'equal)`.
      `(register-cp-handler type-string fn)` for plug-in handlers.
      No concrete handlers yet.
      Deps: `6c.1`, `6a.2` · Branch: `feat/6c2-cp-dispatch`

#### Phase 6 handlers (parallelizable once 6c.2 is green)

- [ ] **6d.1** pure snapshot serializer
      `(cp-snapshot-payload screen)` → plist suitable for cp-encode:
      `(:type "snapshot-reply" :text "..." :html "..." :rows R :cols C)`.
      Pure function. Unit test against a 2×2 synthetic screen.
      Deps: `6a.2`, `5g` · Branch: `feat/6d1-snapshot-pure`

- [ ] **6d.2** snapshot WS handler
      `(register-cp-handler "snapshot" ...)` — on request, calls
      `cp-snapshot-payload`, sends reply to requesting client.
      Integration test: send snapshot request, verify reply shape.
      Deps: `6c.2`, `6d.1`, `6b.3` · Branch: `feat/6d2-snapshot-wire`

- [ ] **6e.1** pure input validator
      `(cp-parse-input msg-plist)` → `(:data "string")` or signals
      `cp-protocol-error` on bad/missing `:data` field.
      Pure function. Unit tests for valid, missing, empty data.
      Deps: `6a.2` · Branch: `feat/6e1-input-pure`

- [ ] **6e.2** input → PTY stdin wire
      `(register-cp-handler "input" ...)` — validated data string
      written to session's PTY stdin stream.
      Deps: `6c.2`, `6e.1`, `6b.3` · Branch: `feat/6e2-input-wire`

#### Phase 6 broadcast (depends on 6d.2 + 6e.2)

- [ ] **6f.1** multi-client session tracking (pure)
      Add `:clients` slot (list) to session entry.
      `(session-add-client session-id client)`,
      `(session-remove-client session-id client)`,
      `(session-broadcast session-id msg-string)` → sends to all.
      Thread-safe via session lock. Pure struct ops, no WS dependency.
      Unit test: add 3 fake clients, broadcast, verify count.
      Deps: `6b.2` · Branch: `feat/6f1-broadcast-struct`

- [ ] **6f.2** wire PTY output pump → broadcast
      PTY stdout reader thread calls `session-broadcast` instead of
      sending to a single client.
      Deps: `6f.1`, `6d.2`, `6e.2` · Branch: `feat/6f2-broadcast-wire`

- [ ] **6f.3** scenario test: two fake clients receive same output
      `tests/cp-scenario.lisp`. Spawn one CP session with bash,
      attach two fake WebSocket clients, send `echo hi`, assert
      both fake clients receive "hi" in their message log.
      Skip on Windows.
      Deps: `6f.2` · Branch: `feat/6f3-broadcast-test`

---

## Track D — Agent integration (after Phase 6)

### Phase 7: claude on the terminal

#### Phase 7 research (docs only, parallel-safe)

- [ ] **7r.1** document claude -p tool_use text format
      `docs/claude-tool-use-format.md`. Run `claude -p` with a
      prompt that triggers a tool call. Capture raw stdout. Document
      exactly what the serialized `tool_use` block looks like:
      delimiter lines, JSON envelope, field names.
      Include 2–3 real captured examples.
      Deps: `-` · Branch: `docs/7r1-tool-use-format`

- [ ] **7r.2** research streaming JSON fragment detection
      `docs/tool-use-stream-parse.md`. Survey strategies for detecting
      a complete JSON object in a character-by-character stream:
      brace counting, delimiter patterns, partial-parse retry.
      Recommend one approach for 7a.1.
      Deps: `7r.1` · Branch: `docs/7r2-stream-parse`

#### Phase 7 pure parsers (parallel-safe, no CP dep)

- [ ] **7a.1** tool-call block detector (pure)
      `src/tool-call.lisp`. `(find-tool-use-block string start)`
      → `(:start N :end M :json "...")` or nil.
      Uses approach from 7r.2 (brace counting or delimiter).
      Unit tests against captured examples from 7r.1.
      No process, no WS, no CP.
      Deps: `7r.1`, `7r.2` · Branch: `feat/7a1-toolcall-detect`

- [ ] **7a.2** tool-call JSON parser (pure)
      `(parse-tool-use json-string)`
      → `(:id "..." :name "list_photos" :input {...})` plist.
      Validates required fields, signals `tool-parse-error` on malformed.
      Unit tests for valid + invalid shapes.
      Deps: `7a.1` · Branch: `feat/7a2-toolcall-parse`

- [ ] **7b.1** tool-result JSON formatter (pure)
      `(format-tool-result tool-use-id result-data)`
      → JSON string in Anthropic tool_result format that claude -p
      expects on stdin.
      Pure function. Unit tests: result round-trips as valid JSON,
      tool_use_id field present.
      Deps: `7r.1` · Branch: `feat/7b1-tool-result-fmt`

#### Phase 7 tool registry (parallel with 7a.*/7b.1)

- [ ] **7c.1** tool registry infrastructure
      `src/tool-registry.lisp`. `defvar *tool-registry*` hash-table.
      `(register-tool name fn)`, `(dispatch-tool name input)`.
      `dispatch-tool` returns result or signals `tool-not-found`.
      Unit tests: register a lambda, dispatch, missing-name error.
      No specific tools — pure infrastructure.
      Deps: `-` · Branch: `feat/7c1-tool-registry`

- [ ] **7c.2** `list_photos` tool
      `src/tool-list-photos.lisp`. Reads `*photos-root*` directory,
      returns a JSON-encodable list of relative paths.
      Registers itself via `(register-tool "list_photos" ...)` at
      load time. Unit test: directory with 3 dummy files → list of 3.
      Deps: `7c.1` · Branch: `feat/7c2-list-photos`

#### Phase 7 integration (sequential, gates on 7a.*/7b.1/7c.1)

- [ ] **7d.1** agent-spawn-cp
      `src/agent-cp.lisp`. `(agent-spawn-cp session-id prompt)`
      launches `claude -p prompt` (using `%claude-command` from
      `src/agent.lisp`) as a child process attached to a CP session.
      Returns child-process struct. No tool interception yet.
      Smoke test: spawn with a trivial prompt, session alive.
      Deps: `6b.3`, `7c.1` · Branch: `feat/7d1-agent-spawn`

- [ ] **7d.2** tool intercept loop
      Background thread reads agent stdout, accumulates buffer,
      calls `find-tool-use-block`. On match:
        1. `parse-tool-use` → tool name + input
        2. `dispatch-tool` → result
        3. `format-tool-result` → JSON
        4. write JSON + newline to agent stdin
      Non-tool output forwarded to `session-broadcast` as-is.
      Unit test: feed a recorded stream with one embedded tool_use,
      assert dispatch called once and result written to fake stdin.
      Deps: `7d.1`, `7a.2`, `7b.1`, `7c.1` · Branch: `feat/7d2-tool-loop`

- [ ] **7d.3** multi-tool + partial-block edge cases
      Extend 7d.2's intercept loop to handle:
      - tool_use block split across two read chunks
      - multiple tool_use calls in a single response
      - tool dispatch error → write `{"type":"error",...}` result
      Unit tests only — no new process spawning.
      Deps: `7d.2` · Branch: `feat/7d3-tool-loop-edge`

- [ ] **7e** end-to-end scenario
      Browser at `/shell`, agent spawned via 7d.1, sends a prompt
      that triggers `list_photos`, result reflected on screen.
      Screenshot (`docs/phase7-e2e.png`) committed as evidence.
      Deps: `7d.2`, `7c.2` · Branch: `main`

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

- **Claude Sonnet**: good at Phase 2 integration, `3c`–`3f`, `5e.*`
  appliers, `6c.*`–`6f.*` WS wiring, `7d.*` intercept loop,
  scenario tests. Hands off ConPTY bindings (`3a.*`).
- **Gemini**: good at pure-data spec-driven work: `3r.*` / `6r.*` / `7r.*`
  research docs, `5e.4a` SGR parser, `6a.2` JSON helpers,
  `7a.1`/`7a.2`/`7b.1` pure parsers, `7c.1` registry infra.
  Not for `3a.*` / `3b.*` or anything with live TUI interactions.
- **Main Claude** (orchestrator): owns `3a.*` / `3b.*` review,
  `7d.*` integration sign-off, and `7e` e2e screenshot.
- **Codex**: equally good as Claude Sonnet; good fallback for
  `6b.*` session registry and `7c.2` list_photos tool.

## Parallel candidates right now (all unblocked)

Research track (purely additive, docs-only, start anytime):
- **3r.1** ConPTY API surface → `docs/conpty-api.md`
- **3r.2** ConPTY wrapper reference → `docs/conpty-wrappers.md`
- **3r.3** ghostty-web CP read → `docs/ghostty-web-cp.md`
- **3r.4** CFFI Windows types → `docs/cffi-windows-types.md`
- **6r.1** JSON line framing → `docs/cp-framing.md`
- **6r.2** cl-json library survey → `docs/cp-json-lib.md`
- **7r.1** claude -p tool_use format → `docs/claude-tool-use-format.md`

Unit test track (covers current `main`):
- **UT1** tests for `src/proc.lisp` functions (spawn-child, handle
  bundle accessors, stdio stream accessors)
- **UT2** tests for `src/term.lisp` (WebSocket resource registration,
  echo handler round-trip, localhost guard when applicable)
- **UT3** tests for `src/main.lisp` handlers (start/stop idempotent,
  acceptor lifecycle)
- **UT4** tests for `src/agent.lisp` pure helpers (agent-alive-p
  semantics with no process, agent-stdin/agent-stdout returning nil)

Phase 6 pure atoms (no M1 dep, start immediately):
- **6b.1** session-id generator — pure, trivial
- **7c.1** tool registry — pure infra, no deps at all
- **7r.2** stream-parse research — once `7r.1` lands

Track B Phase 5 tasks with no cross-file deps beyond `5c`:
- **5a**, **5b**, **5c** sequential foundation
- Once `5c` lands: **5e.1** (dispatcher), then **5e.2**, **5e.3**,
  **5e.4a**, **5e.5** can all proceed in parallel.
- **5e.4a** is doubly-parallel: pure function, start right now.
- **5d** scrollback parallel with `5e.2`/`5e.3`/`5e.4*`.

Track A Phase 3 implementation is gated on `3r.*` research:
- `3a.1` can start once `3r.1` + `3r.4` land.
- `3a.2` waits on `3a.1`.
- `3b.1` is Unix-only, can start anytime.

## Rules

- Pick one task per agent. Do not double-assign.
- Research tasks (`3r.*`) are purely docs — no code changes.
- The unit-test track (UT*) lives on main-adjacent branches
  (`feat/ut1-proc`, `feat/ut2-term`, etc.) and should land as
  separate PRs, not bundled.
- Sequential within Phase 5 handlers: `5c` must land before the
  parallel fan-out of `5e.*`.

---

## Track T — Tier Fast Path (issue #19)

Purpose: compress the path from "CP wires up" to the **dogfood verdict**
(`docs/tier-3-verdict.md` = KEEP | ARCHIVE). Everything in Track T is
subordinate to Issue #19's acceleration tactics.

Freezes in effect while Track T is open:
- Phase 5 (screen buffer), Phase 6f (broadcast), Phase 7 (tool intercept)
  are **frozen**. Do not add atoms there.
- No new backlog atoms may be opened outside Track T until T2 demo exists.

Design memo: see `docs/tier-breakdown.md` for per-tier rationale,
data-flow diagrams, and the Tier-3 candidate-task decision.

### Tier 1 — Wire up (Atom 17.x ∪ deckpilot #27)

- [x] **T1.a** verify deckpilot `/ws` endpoint reachable from Lisp side
      Implements: `docs/tier-1/ws-handshake.log`
      Deps: deckpilot #27 (external, closed 2026-04-20) · Branch: `feat/t1a-ws-smoke`
      DoD: committed log file showing successful WS handshake against
           `ws://127.0.0.1:8080/ws` from `cp-client`, with request/response bytes.
      Done: 2026-04-21 — LIST returned OK=T with 29 sessions; STATE returned
            expected "session not found" error; `tier-1-smoke.lisp` in-package
            bug also fixed (was at COMMON-LISP-USER).
      Est: 1h · Agent hint: Claude Sonnet | Codex

- [ ] **T1.b** CP round-trip smoke: INPUT / SHOW / STATE / LIST
      Implements: `scripts/cp-smoke.lisp`, `docs/tier-1/cp-roundtrip.log`
      Deps: T1.a · Branch: `feat/t1b-cp-smoke`
      DoD: one script that sends each of the 4 verbs and prints JSON
           replies; committed log shows all 4 receive non-error responses.
      Est: 2h · Agent hint: Claude Sonnet

- [ ] **T1.c** `scripts/boot-hub.lisp` exits 0 with green log
      Implements: `scripts/boot-hub.lisp` (review/harden existing), `docs/tier-1/boot-hub.log`
      Deps: T1.b · Branch: `feat/t1c-boot-hub`
      DoD: `sbcl --script scripts/boot-hub.lisp` exits 0, stdout captured
           to `docs/tier-1/boot-hub.log`, no unhandled conditions.
      Est: 1-2h · Agent hint: Claude Sonnet

- [ ] **T1.d** Tier-1 completion evidence commit
      Implements: `docs/tier-1/README.md` (index of logs) + all T1.* logs
      Deps: T1.a, T1.b, T1.c · Branch: `feat/t1d-tier1-evidence`
      DoD: `docs/tier-1/` contains handshake + roundtrip + boot logs and
           a one-paragraph README pointing to each.
      Est: 0.5h · Agent hint: Claude Sonnet | Gemini

### Tier 2 — Minimal vertical slice

Scope lock: one browser page, one iframe, one button, one fixed agent.
Anything that does not shorten the path to the T2.h screenshot is out
of scope.

- [x] **T2.a** iframe wiring to ghostty-web in business-ui case view
      Implements: `src/business-ui.lisp` (case-view-handler HTML emit)
      Deps: T1.c · Branch: `feat/t2a-iframe-wire`
      DoD: loading `/cases/:id` renders a live ghostty-web terminal in
           an iframe; raw ghostty-web URL taken from a `*ghostty-web-url*`
           parameter (no hardcoded port).
      Done: 2026-04-21 — already in `src/business-ui.lisp` (line 22 defines
            `*ghostty-web-url*` defaulting to env `GHOSTTY_WEB_URL` or
            `/shell`; line 136 renders `<iframe src="~a/shell?case=~a">`
            interpolating that parameter). De-facto complete before Track T.
      Est: 1-2h · Agent hint: Claude Sonnet

- [ ] **T2.b** CP INPUT trigger button on case view
      Implements: `src/business-ui.lisp`, `src/cp-ui-bridge.lisp` (new)
      Deps: T2.a, T1.b · Branch: `feat/t2b-input-button`
      DoD: a `<form method=post>` button on `/cases/:id` sends a
           fixed command (e.g. `echo hello from hub`) to the fixed agent
           via `pipeline-cp:send-input`; server returns 200.
      Est: 2h · Agent hint: Claude Sonnet | Codex

- [ ] **T2.c** fixed single-agent session selection
      Implements: `scripts/boot-hub.lisp` (spawn one claude session via
                  deckpilot on boot, store id in `*demo-session-id*`),
                  `docs/tier-2/agent-choice.md`
      Deps: T2.b · Branch: `feat/t2c-fixed-agent`
      DoD: boot script creates exactly one agent session on startup;
           `*demo-session-id*` resolvable from Lisp REPL; rationale for
           picking `claude -p` (vs gemini / codex) documented.
      Est: 1-2h · Agent hint: Main Claude

- [ ] **T2.d** end-to-end round-trip reflected in iframe
      Implements: manual test script `scripts/t2-e2e.lisp` (+ log)
      Deps: T2.a, T2.b, T2.c · Branch: `feat/t2d-e2e`
      DoD: pressing the T2.b button causes the iframe's terminal pane
           to visibly display the agent's output within 5s; captured log
           `docs/tier-2/e2e.log` shows WS frames for INPUT→broadcast.
      Est: 2h · Agent hint: Claude Sonnet

- [ ] **T2.e** one-command boot (`make demo` or `sbcl --script scripts/demo.lisp`)
      Implements: `Makefile` (or `scripts/demo.lisp`), `docs/tier-2/boot.md`
      Deps: T2.c · Branch: `feat/t2e-make-demo`
      DoD: a single command from repo root starts ghostty-web + deckpilot
           + hub, opens a browser to `/cases/:id`, and exits cleanly on
           Ctrl-C; documented in `docs/tier-2/boot.md`.
      Est: 2-3h · Agent hint: Claude Sonnet | Codex

- [ ] **T2.f** usage-log instrumentation stub
      Implements: `src/cp-ui-bridge.lisp` — every CP `INPUT` emitted
                  from the UI appends a line to `~/.photo-ai-lisp/usage.log`.
      Deps: T2.b · Branch: `feat/t2f-usage-log`
      DoD: clicking the T2.b button adds a line shaped
           `<iso-ts>\t<verb>\t<session>\t<bytes>` to the log; test asserts
           one click → one line.
      Est: 1h · Agent hint: Gemini | Codex

- [ ] **T2.g** Tier-2 demo screenshot + committed log
      Implements: `docs/tier-2/demo.png`, `docs/tier-2/demo.log`,
                  `docs/tier-2/README.md`
      Deps: T2.d, T2.e · Branch: `feat/t2g-evidence`
      DoD: PNG shows business-ui page with iframe populated by agent
           output; log is the matching `docs/tier-2/e2e.log` from T2.d.
      Est: 0.5h · Agent hint: Main Claude

### Tier 3 — Dogfood week

Pre-condition for starting Tier 3: all of Tier 2 checked.

- [x] **T3.a** lock the "real task" up front
      Implements: `docs/tier-3/real-task.md` (decision, not menu)
      Deps: T2.g · Branch: `feat/t3a-real-task`
      DoD: file states exactly one task (recommended: photo-import
           pipeline via Lisp hub), lists its inputs, outputs, and the
           daily usage it will replace. No "we will decide later".
      Done: 2026-04-21 — locked photo-import pipeline via Lisp hub (matches
            daily CLI use); KEEP threshold = ≥15 INPUTs/week.
      Est: 1h · Agent hint: Main Claude

- [x] **T3.b** usage-log verb taxonomy frozen
      Done: 2026-04-21 — `docs/tier-3/usage-log-format.md` freezes 6 verbs
            (INPUT/SHOW/STATE/LIST/BOOT/SHUTDOWN), TSV line format, byte
            semantics per verb, and KEEP/ARCHIVE counting rules.
      Implements: `docs/tier-3/usage-log-format.md`
      Deps: T2.f · Branch: `feat/t3b-log-format`
      DoD: file defines the closed set of verbs (`INPUT`, `SHOW`,
           `STATE`, `LIST`, `BOOT`, `SHUTDOWN`) and byte-count semantics
           so later counting is unambiguous.
      Est: 0.5h · Agent hint: Gemini

- [x] **T3.c** daily checkpoint template
      Implements: `docs/tier-3/checkpoints/TEMPLATE.md`
      Deps: T3.a, T3.b · Branch: `feat/t3c-checkpoint-template`
      DoD: template captures per-day: hub-driven command count vs
           terminal-driven, blockers, UX frustrations, time-to-task.
      Est: 0.5h · Agent hint: Gemini

- [x] **T3.d** KEEP/ARCHIVE quantitative criteria
      Implements: `docs/tier-3/verdict-criteria.md`
      Deps: T3.c · Branch: `feat/t3d-criteria`
      DoD: criteria are numeric and pre-registered — e.g. KEEP iff
           `hub_commands / (hub_commands + cli_commands) ≥ 0.4`
           **AND** `frustration_count ≤ 5/day average` across the week.
           ARCHIVE otherwise. No vibe-based judgment.
      Est: 1h · Agent hint: Main Claude

- [ ] **T3.e** dogfood week execution log (one atom per weekday)
      Implements: `docs/tier-3/checkpoints/{mon,tue,wed,thu,fri}.md`
                  (five files from the T3.c template)
      Deps: T3.c, T3.d · Branch: `feat/t3e-dogfood-log`
      DoD: five checkpoint files exist, each filled from the template
           using that day's actual `usage.log` counts.
      Est: 5 × 0.5h over the week · Agent hint: Main Claude

- [ ] **T3.f** `docs/tier-3-verdict.md` — KEEP | ARCHIVE
      Implements: `docs/tier-3-verdict.md`
      Deps: T3.e · Branch: `feat/t3f-verdict`
      DoD: top line is literally `KEEP` or `ARCHIVE`; below it,
           computed ratio + frustration count vs T3.d criteria + link
           to each T3.e checkpoint. Closes Issue #19.
      Est: 1h · Agent hint: Main Claude

### Post-verdict

- [ ] **T.KEEP.next** if KEEP: unfreeze Phase 5 / Phase 7 and re-queue
      Implements: re-open Phase 5 / Phase 7 atoms in this file
      Deps: T3.f = KEEP
- [ ] **T.ARCHIVE.next** if ARCHIVE: freeze Lisp hub, retain deckpilot
      `/ws` as public API, annotate this backlog with archival note
      Implements: `docs/archive-note.md`
      Deps: T3.f = ARCHIVE
