# Handover — 2026-04-18 night (Phase 5 wrap-up)

Read this first, then `LESSONS.md`. Previous handover is in git history.

## TL;DR (updated 2026-04-18 22:00 — regression fixed)

Phase 5 (screen + html + handlers) is **12/12 atoms landed** on
`track-b/ansi-parser`. The test loader regression that silently
dropped the suite to 49 of ~270 checks has been fixed: root cause
was three orphan `cp -r` snapshots under
`~/quicklisp/local-projects/` whose stale `photo-ai-lisp.asd` files
shadowed the live worktree. See `LESSONS.md` §"Phase 5 267→49
regression" for full diagnosis.

Current canonical verification:

```bash
cd ~/photo-ai-lisp-track-b
'/c/Users/yuuji/SBCLLocal/PFiles/Steel Bank Common Lisp/sbcl.exe' \
  --non-interactive \
  --eval "(require 'asdf)" \
  --eval "(asdf:test-system :photo-ai-lisp/tests)"
```

Expected and observed: **267 checks, 0 fail**, including
`SCREEN-SCENARIO-HELLO-WORLD-VIA-PARSER`.

The remainder of this document describes the original Phase 5 state
for historical context and lists the hygiene tasks that are now done.

## What landed in Phase 5

`track-b/ansi-parser` log (newest first):

```
8dd9318 feat(screen): 5h — integration scenario + cr/lf handlers
e426c6d feat(screen): 5g — screen->html with attr span runs
eef5b12 feat(screen): 5e.5 — simple controls with scroll-on-lf
59c2917 feat(screen): 5e.4b — apply SGR to cursor attrs
8c6fb24 feat(screen): 5e.3 — erase-display and erase-line
07237a3 feat(screen): 5e.2 — cursor-move and cursor-position
9978ef0 feat(screen): 5f  screen->text snapshot
c8dbde5 feat(screen): 5e.1  apply-event dispatcher + :print handler
7143e57 feat(screen): 5d  scrollback ring capped at 1000
7b752cf feat(screen): 5c  cursor model with clamped movement
52c5bf6 feat(screen): 5b — screen grid + infra fixes
e5e1b6e Merge track-b/5e4a-sgr-parse: pure SGR param parser
e06603c feat(screen): 5a — cell struct with defaults, copy, equal tests
```

Source layout the suite produced:

- `src/screen.lisp` — cell struct, screen grid, cursor, scrollback,
  `register-event-handler` / `apply-event`, `:print`/`:cr`/`:lf` handlers
- `src/screen-events.lisp` — handlers for cursor-move, cursor-position,
  erase-display, erase-line, set-attr, simple controls
- `src/sgr.lisp` — pure SGR param parser
- `src/screen-html.lisp` — `screen->html` with attribute span runs
- `tests/screen-tests.lisp` (41 deftests)
- `tests/screen-scenario.lisp` (1 integration deftest — Hello\r\nWorld)
- `tests/sgr-tests.lisp` (35 deftests)
- `tests/ansi-tests.lisp` (9 deftests)

## The blocker — test loader regression

**Symptom.** Both `(asdf:test-system :photo-ai-lisp/tests)` and
`(5am:run-all-tests)` print only:

```
Running test suite ANSI-TESTS
Running test suite SCREEN-TESTS
  Running test CELL-DEFAULTS .....
  Running test CELL-COPY ....
  Running test CELL-EQUAL ..
 Running test AGENT-SENDS-PROMPT-AND-GETS-RESPONSE ..
Did 49 checks. Pass: 49 (100%)
```

Expected: ~270 checks across ANSI-TESTS (9), SCREEN-TESTS (41),
SCREEN-SCENARIO (1), SGR-TESTS (35), agent-scenario (1).

What is missing:

1. SCREEN-TESTS only runs the first 3 deftests (CELL-DEFAULTS,
   CELL-COPY, CELL-EQUAL) — the remaining 38 are silently absent.
2. SGR-TESTS suite never starts. `tests/sgr-tests.lisp` defines
   `(def-suite sgr-tests :in photo-ai-lisp-tests)` and 35 deftests —
   none register.
3. SCREEN-SCENARIO test (the new 5h integration test in
   `tests/screen-scenario.lisp`, registered with
   `(in-suite photo-ai-lisp-tests)`) never runs.

**No errors are printed.** Exit code is 0. Compile is silent.

Note: The previous run shown in the (now-deleted) `sbcl-test.log` at
21:02 reported 267 checks — meaning at some prior point the loader
*was* working. The regression is not from 5h itself; it predates 5h.

**Hypotheses (not verified) — start here:**

- `tests/package.lisp` may be missing exports / suite forward-decls
  that `sgr-tests.lisp` and `screen-scenario.lisp` need at load time.
  Check whether SGR-TESTS is even *defined* in the running image
  after `(asdf:load-system :photo-ai-lisp/tests)`.
- ASDF may be reusing a stale FASL of `tests/screen-tests.lisp` from
  before the file grew past 3 deftests. Force `(asdf:operate
  'asdf:compile-bundle-op :photo-ai-lisp/tests :force t)` or wipe the
  Windows ASDF cache (lives under `~/AppData/Local/cache/common-lisp/`,
  not `~/.cache/`).
- The `eef5b12` (5e.5) commit added the `screen-events` file in the
  middle of the `:components` list; double-check `photo-ai-lisp.asd`
  puts `screen` before `screen-events` before `sgr` before
  `screen-html`. The 5h commit also has CRLF churn on those lines —
  rule out an editor that broke the form.

**Verification command** once fixed:

```bash
cd ~/photo-ai-lisp-track-b
'/c/Users/yuuji/SBCLLocal/PFiles/Steel Bank Common Lisp/sbcl.exe' \
  --non-interactive \
  --eval "(require 'asdf)" \
  --eval "(asdf:test-system :photo-ai-lisp/tests)"
```

Expected: ~270 checks, 0 fail, including
`SCREEN-SCENARIO-HELLO-WORLD-VIA-PARSER`.

## Next-team mission (in order)

1. **Fix test loader.** All 4 suites must register and run. Threshold:
   ≥ 270 passing checks, 0 fail. No skip. (Do NOT delete tests to make
   the loader green — the tests are the spec.)
2. **Confirm 5h passes** under the now-working loader. The scenario
   feeds `Hello\r\nWorld` through `make-parser` →
   `parser-feed-string` → `apply-event` → `screen->text` and asserts
   the snapshot contains both strings. If it fails, the bug is in the
   :cr / :lf handler interaction with the `:print` handler — note
   that 5h registered duplicate :cr/:lf handlers in `src/screen.lisp`
   (5e.5 already had them in `src/screen-events.lisp`); the duplicate
   is harmless (last-write-wins in the hash table) but should be
   collapsed into one location during the fix.
3. **Merge `track-b/ansi-parser` → `main`** once verified. Branch is
   on fork only; no upstream concerns.
4. **Phase 6 + 7.** See `BACKLOG.md` for the parallel-safe atoms
   already broken down. Same orchestration model: spine session +
   handlers session + Codex worker.

## Hygiene to clean up while you're in there

- `photo-ai-lisp.asd` 5h commit included CRLF/LF line-ending churn on
  `screen-events` / `screen-html` lines. Normalize.
- `html` is a 0-byte file in repo root left behind by an experimental
  `screen->html` write. Delete and `.gitignore`.
- `sbcl-test.log` is a transient. `.gitignore` `*-test.log`.

## Orchestration state at handover time

- `track-b/ansi-parser` is up to date on `origin` (fork:
  `YuujiKamura/photo-ai-lisp`). `main` is behind by Phase 5.
- Deckpilot sessions `ghostty-37928` (spine), `ghostty-38136`
  (handlers), `ghostty-36224` (Codex), `ghostty-15524` (Codex relief)
  were all stuck in display-only "Working …" states by the end of the
  Phase 5 race. Their work is fully harvested into `8dd9318`. Kill
  them on the next session start; do not try to resume.
- `ghostty-win` itself crashed with `EXCEPTION 0x80000003` in
  `App.zig:1375 nci.close()` during `fullCleanup` when deckpilot tried
  to spawn a new session. Unrelated to photo-ai-lisp; reproduce
  standalone in ghostty-win project before the next deckpilot run.

## Race lessons (file these in LESSONS.md)

- "267 tests passing" in a worker's log is not proof. Always re-run
  the full suite from a clean shell before declaring a milestone done.
  In this race the workers reported green for 5g, but the same loader
  has been silently dropping ~80% of tests for an unknown number of
  commits.
- Codex sessions can sit at "Working …" for 15+ minutes after the
  underlying shell has already exited (PowerShell `tee`-based wrapper
  in particular). Use the test log file mtime, not the agent's UI
  state, to decide whether work is still in flight.
- Two parallel Codex workers on the same FASL cache will produce
  ambiguous "Working" indicators while not actually competing for
  work. One worker per cache scope.

## Reference

- `LESSONS.md` — design decisions (CP protocol, why no go binary, etc.)
- `BACKLOG.md` — Phases 2–7 atomic task breakdown
- `docs/3bst-reference.md` — terminal scrollback semantics reference
  used by the 5e family
- `docs/skill-cli.md` — probed CLI shape per photo-* skill
- `~/reference/3bst/` — full reference implementation tree
