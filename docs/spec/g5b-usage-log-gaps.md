# G5.b — usage-log defer gap atom decomposition

**status**: draft, atom-level only (implementation post-Fri 2026-04-24 verdict)
**base**: main @ 60a9a98 (C1 landed)
**verdict invariance**: `\tINPUT\t` grep contract is preserved across all atoms

## Current state (C1 landing summary)

- **log file**: `~/.photo-ai-lisp/usage.log` (1-line-per-record, tab separated)
- **errors file**: `~/.photo-ai-lisp/usage-errors.log` (unknown verb / bad bytes sink)
- **current record schema**: 4 tab-separated fields
  `<iso8601-ts>\t<verb>\t<session>\t<bytes>` (per `docs/tier-3/usage-log-format.md`)
- **closed verb set** (already frozen in spec):
  `INPUT / SHOW / STATE / LIST / BOOT / SHUTDOWN`
- **writer API**: `write-usage-log-event` in `src/usage-log.lisp` already takes
  `:verb / :session / :bytes` keyword args. Verb param is in place; only the
  call sites are missing.
- **what C1 actually wired**: one call site at
  `src/cp-ui-bridge.lisp:154-158` (Mode 1, shell-broadcast demo path). It
  passes `:verb "INPUT"` hard-coded and wraps in `IGNORE-ERRORS` so a
  filesystem hiccup cannot 503 a successful broadcast.
- **log coverage today**:
  - Mode 1 (shell-broadcast via `input-bridge-handler`) INPUT: logged
  - Mode 2 (REPL direct via `live-eval-handler` / `live-eval`): silent
  - Legacy CP envelope path (`input-bridge-handler` else-branch via
    `send-cp-command`, lines 172-197): silent
  - Hub boot (`start` in `src/main.lisp:115`): silent
  - Hub shutdown (`stop` in `src/main.lisp:128`): silent
  - Timing (latency ms) per record: absent

## Verdict-invariance constraint

The Fri 2026-04-24 counting script greps `\tINPUT\t` on the main log and
counts distinct lines with `bytes > 0`. Every atom below MUST preserve:

1. `INPUT` lines remain the ONLY lines matching `\tINPUT\t` (new verbs use a
   different column-2 string — already guaranteed by closed verb set).
2. New verbs land in the same file (`usage.log`), not a side file, so their
   existence does not shift the INPUT population.
3. Column-2 position (verb) stays stable. G5.b.3 appends to the end, never
   in the middle.

## Atom G5.b.1 — Mode 2 (REPL direct) hook

### gap
`src/live-repl.lisp`'s `live-eval` / `live-eval-handler` accept arbitrary
S-expressions from localhost (DSL-style hot-patching), but produce zero
usage-log records. This undercounts dogfood activity during verdict week
for anyone driving the hub via `curl -X POST /api/eval`.

### affected files
- `src/live-repl.lisp` — add `write-usage-log-event` call inside
  `live-eval-handler` after a successful read+eval, before returning JSON.
- `src/usage-log.lisp` — no change; `write-usage-log-event` already exported
  via `src/package.lisp:83`.

### implementation sketch
- In `live-eval-handler`, after the `(live-eval body)` call succeeds,
  issue `(ignore-errors (write-usage-log-event :verb "INPUT" :session "-"
  :bytes (usage-log-utf8-byte-count body)))`.
- Session is `-` (BOOT/SHUTDOWN-style placeholder) because `/api/eval`
  carries no deckpilot session; this is an operator-driven REPL hit, not
  an agent session.
- Bytes is the raw posted body length (pre-eval), matching the Mode 1
  semantic of "UTF-8 bytes of the thing the user typed."
- Log BEFORE returning the response body so a write failure cannot
  silently succeed the request; wrap in `IGNORE-ERRORS` so a disk hiccup
  cannot 500 a successful eval.
- Only log on `(getf r :ok)` path; `:error` path writes to `usage-errors.log`
  is tempting but out of scope (that log is for spec violations, not for
  user-visible eval errors).

### LoC estimate
~6 lines in `live-eval-handler` (1 `ignore-errors` + 1 `write-usage-log-event`
form with 3 keyword args + trailing paren).

### verification
- fiveam: bind `*usage-log-path*` to a temp file, POST a form to
  `live-eval-handler` (or call `live-eval` then the handler layer directly),
  read the temp file, assert it contains exactly one line matching
  `\tINPUT\t-\t<byte-count>\n`.
- fiveam: ensure malformed body (e.g., `(def`) does NOT produce a main-log
  line (`:error` path writes nothing to `usage.log`).
- manual: `curl -X POST --data '(+ 1 1)' http://127.0.0.1:8090/api/eval`
  then `tail -1 ~/.photo-ai-lisp/usage.log` shows an INPUT record with
  bytes = 7.

### depends on
None. Independent; can land before G5.b.2 / G5.b.3.

## Atom G5.b.2 — BOOT + SHUTDOWN verbs at hub lifecycle

### gap
Hub `start` and `stop` (`src/main.lisp:115` / `:128`) do not write BOOT /
SHUTDOWN records. The spec in `docs/tier-3/usage-log-format.md` already
defines both verbs with `bytes = 0` and `session = -`, but no code path
emits them. Consequence: `usage.log` has no session boundaries, so a
crash vs. clean shutdown is not distinguishable offline, and the INPUT
density per hub-uptime cannot be computed.

### affected files
- `src/main.lisp` — add `write-usage-log-event` call at the end of `start`
  (after `(hunchentoot:start *acceptor*)`) and at the beginning of `stop`
  (before `(hunchentoot:stop *acceptor*)`).
- `src/usage-log.lisp` — no change. Verb set already includes BOOT +
  SHUTDOWN; writer API already parametric on `:verb`.

### implementation sketch
- In `start`: after the `hunchentoot:start` line, inside the `unless`
  branch (so we only log on actual boot, not on the idempotent re-call
  path), add
  `(ignore-errors (write-usage-log-event :verb "BOOT" :session "-" :bytes 0))`.
- In `stop`: inside the `when *acceptor*` branch, before the
  `hunchentoot:stop` call, add
  `(ignore-errors (write-usage-log-event :verb "SHUTDOWN" :session "-"
  :bytes 0))`. Logging before stop keeps the log write ordered causally
  with the service still existing; if `hunchentoot:stop` itself errors,
  we still have the SHUTDOWN intent on record.
- `IGNORE-ERRORS` per C1 precedent — log plumbing must never break the
  lifecycle entry points.
- `boot-hub.lisp`'s `run-demo` calls `(start :port 8090)`, so BOOT logs
  for free without touching the script.

### verification
- fiveam: bind `*usage-log-path*` to temp, call `(start :port <free-port>)`
  then `(stop)`, read temp file, assert two lines in order
  `\tBOOT\t-\t0\n` then `\tSHUTDOWN\t-\t0\n`.
- fiveam (invariance): on the temp file from above,
  `(count-matches "\\tINPUT\\t" contents)` must be 0. This proves BOOT /
  SHUTDOWN do not bleed into the verdict grep.
- manual: boot hub, immediately `tail -1 ~/.photo-ai-lisp/usage.log`
  → BOOT line; `Ctrl-C` or call `(stop)` → SHUTDOWN line appended.
  `grep "\tINPUT\t" ~/.photo-ai-lisp/usage.log` count unchanged.

### LoC estimate
~8 lines total across `start` (~4) and `stop` (~4).

### depends on
Independent from G5.b.1. Can land in parallel. Ordering note: if
G5.b.2 lands first, BOOT records for every hub restart start accumulating
immediately, which is the desired behavior; no replay of historical
uptime is attempted.

## Atom G5.b.3 — ms phase (latency field)

### gap
No per-record duration, so latency verdicts ("was INPUT slow?", "did SHOW
regress?") need out-of-band profiling. Adding a `<duration-ms>` field
turns `usage.log` into a cheap latency histogram source for free.

### affected files
- `docs/tier-3/usage-log-format.md` — schema change: 4 fields → 5 fields.
  This is a SPEC change, not just a code change. Must call out "additive,
  column-2 unchanged, INPUT grep still matches."
- `src/usage-log.lisp` — extend `write-usage-log-event` to accept
  `:duration-ms` (integer, default 0 or `-`), append as the 5th
  tab-separated field. Keep the existing 4-field format-directive and
  add one more `~C~A` / `~C~D` tail.
- `src/cp-ui-bridge.lisp` — at the Mode 1 (shell-broadcast) call site,
  capture `(get-internal-real-time)` before `shell-broadcast-input` and
  after, compute `ms = (floor (* 1000 delta) internal-time-units-per-second)`,
  pass as `:duration-ms`.
- `src/live-repl.lisp` — if G5.b.1 already landed, bracket the
  `(live-eval body)` call the same way.
- `src/main.lisp` — BOOT / SHUTDOWN (if G5.b.2 already landed) carry
  `:duration-ms 0`; boot-cost instrumentation is out of scope (would
  require earlier probe at image load).

### implementation sketch
- **Field position**: tail of the record, so column 2 (verb) is unchanged.
  New line layout: `<ts>\t<verb>\t<session>\t<bytes>\t<ms>`.
- **Default**: when a call site doesn't instrument, default
  `:duration-ms` to `0` (not `-`) so the field type is always int and the
  parser stays trivial. Downstream consumers treat `0` as "not measured"
  by convention.
- **Writer signature**:
  `(defun write-usage-log-event (&key verb session bytes (duration-ms 0)) ...)`.
- **Timing primitive**: `internal-time-units-per-second` already used in
  `%usage-log-iso8601-utc-now`; reuse the idiom. Multiply-first-then-divide
  to avoid int truncation on fast paths (`<1 tick` bursts).
- **Grep invariance**: INPUT records still match `\tINPUT\t` because we
  only append, never insert. Existing consumers that split on tab and
  stop at index 3 keep working; new consumers read index 4.

### verification
- fiveam: mock a slow `shell-broadcast-input` with `(sleep 0.1)`; assert
  the logged record's 5th field parses to an integer in `[80, 400]` (wide
  Windows-SBCL tolerance). Grep `\tINPUT\t` count still equals the number
  of calls (invariance).
- fiveam: call `write-usage-log-event` without `:duration-ms`; assert the
  5th field is literally `0`.
- fiveam: parse an existing 4-field historical line (hand-crafted into the
  temp file); assert a tolerant reader ignores the missing field without
  crashing. (This exercises the downstream contract; skip if the reader
  lives outside this repo.)
- manual: after one Mode 1 INPUT, inspect the new last line; confirm 5
  tab-separated fields, ts format unchanged, INPUT in column 2.

### LoC estimate
~25 lines total: ~5 in `usage-log.lisp` (keyword arg + format extension),
~4 in `cp-ui-bridge.lisp` (start/end timestamp + delta), ~4 in
`live-repl.lisp` (if G5.b.1 landed), ~3 in `main.lisp` BOOT/SHUTDOWN
carry-through, ~8 lines of docs/spec update for the schema change.

### depends on
- **Sequencing with G5.b.1 / G5.b.2**: G5.b.3 is cleanest if it lands
  AFTER the two new call sites, because the instrumentation
  `(let ((t0 ...)) ... (write-usage-log-event ... :duration-ms delta))`
  is added once per site — re-opening a freshly touched call site has
  lower merge-conflict risk than touching all sites twice.
- Can run in parallel with G5.b.1 / G5.b.2 only if the implementer is
  careful about rebasing; recommended order is serial after.

## Recommended ordering

1. **G5.b.1 (Mode 2 hook)** — smallest diff, independent, exercises the
   same `write-usage-log-event` contract as C1. Good warm-up atom.
2. **G5.b.2 (BOOT + SHUTDOWN)** — parallel with G5.b.1; touches `main.lisp`
   only, no overlap.
3. **G5.b.3 (ms phase)** — serial AFTER 1 + 2 land to minimize re-editing
   the call sites. Includes a spec bump in `docs/tier-3/usage-log-format.md`.

Total LoC across the three atoms: ~40 production lines + ~30 test lines +
~10 doc lines ≈ **80 LoC**. Fits in 1-2 Phase of focused work; suitable for
one Team pass (two atoms in parallel) + one follow-up atom.

## Out of scope

- **Pre-verdict implementation**: no code touches before Fri 2026-04-24
  verdict ships. Even atoms that preserve the `\tINPUT\t` grep contract
  introduce diff churn, CI runs, and possible test flakes that pollute
  the measurement window. The verdict is measured on main @ 60a9a98
  plus any bug-fix-only commits, not on feature additions.
- **Log rotation / retention** — C2 territory; `usage.log` stays
  append-only with no size cap during dogfood week per the spec.
- **Error-log-on-error** — `live-eval-handler` `:error` path does NOT
  write to `usage.log` or `usage-errors.log`. `usage-errors.log` is for
  spec violations (bad verb, bad bytes), not for user-visible eval
  failures. A future atom could widen that scope but it is not a C1-gap.
- **Replay** — no backfill of historical uptime into BOOT records. Every
  hub restart from the landing commit forward emits its own BOOT, and
  pre-existing logs simply do not have them. Consumers must tolerate
  absent BOOT at the start of the file.
- **Streaming / real-time tailing** — `usage.log` remains a flat append
  file, not a message bus. WebSocket streaming of events is a separate
  Tier 3 concern, tracked elsewhere.

## Notes for implementers

- Verb set is FROZEN. Do not introduce a new verb under any of the three
  atoms. The only in-scope additions are call-site hookups (G5.b.1,
  G5.b.2) and a schema append (G5.b.3).
- Keep `IGNORE-ERRORS` on every call site. C1's reasoning holds: a log
  write must never 5xx a successful hub operation or block shutdown.
- The spec change in G5.b.3 is the only doc change in this triad. Bump
  `docs/tier-3/usage-log-format.md` in the same commit that lands the
  5-field schema so there is never a SHA where code and spec disagree.
