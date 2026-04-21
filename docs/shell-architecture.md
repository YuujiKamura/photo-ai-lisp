# /ws/shell Architecture

Scope: the browser-to-`claude` path served by `/ws/shell` on the Lisp hub
(port 8090). Covers the five transport layers between `ghostty-web` in the
`/shell` page and the child `cmd.exe` + agent REPL, plus the observability
and testing surfaces. Written for engineers who need to debug a silent
picker failure, add a new preset, or retarget the transport — not a tour
for new contributors.

Three fix commits anchor this document:

| Commit    | Layer                 | Summary                                                      |
|-----------|-----------------------|--------------------------------------------------------------|
| `de778f7` | 4, 5                  | Route `/ws/shell` cmd.exe through `conpty-bridge`; picker race |
| `e5a19b7` | 3                     | `:external-format :latin-1` on child stdio; drop ignored `:element-type` |
| `2a95c96` | 2                     | `%normalize-child-input` idempotent over consecutive CRs     |

Supporting audit docs: `.dispatch/inject-contract-audit.md`,
`.dispatch/proc-element-type-audit.md`.

---

## Overview

```
  Browser (/shell page)
      │  ghostty-web (WASM terminal emulator)
      │  term.onData: replace \r -> \n  (Layer 1)
      ▼
  WebSocket text frame
      │  hunchensocket (hunchentoot upgrade)
      │  UTF-8 decode -> Lisp string
      ▼
  shell-client (Layer 2)
      │  %normalize-child-input:
      │    - drop code > #xFF
      │    - LF (10) -> CR (13)
      │    - collapse consecutive CRs to one
      ▼
  child-process stdin  (Layer 3)
      │  uiop:launch-program
      │  SBCL fd-stream, element-type CHARACTER,
      │  :external-format :latin-1, bivalent
      ▼
  conpty-bridge.exe    (Layer 4)
      │  io.Copy stdin -> ConPTY master
      │  io.Copy ConPTY master -> stdout
      ▼
  cmd.exe (real ConPTY slave)
      │  pick-agent.cmd: set /p CHOICE="> "
      │                  1 -> claude, 2 -> gemini, 3 -> codex
      ▼
  claude / gemini / codex REPL
```

The `client-connected` handler also fires Layer 5 on a worker thread that
auto-types `scripts\pick-agent.cmd` + one LF into stdin 0.4s after the
socket comes up. Without that auto-inject the user just sees a bare `cmd>`
prompt; with it, the picker menu appears and Enter-1 lands in `claude`.

Source: `src/term.lisp:274-312` (client-connected), `src/proc.lisp:8-55`
(spawn-child), `tools/conpty-bridge/main.go`.

---

## Layer 1: WebSocket wire format

The `/shell` page sends keystrokes verbatim over `/ws/shell` except for
one rewrite: **`\r` becomes `\n` before `ws.send`**. This is a workaround
for a hunchensocket / flexi-streams bug that crashes a text frame carrying
a bare `0x0D` byte with

    NIL is not of type (MOD 1114112)

The error cascades into hunchensocket's outer `handler-bind` in
`read-handle-loop` and closes the socket with status `1011 Internal Error`.
An Enter keystroke would therefore drop the session every single time if
the browser sent its native CR.

The symmetric rule on the Lisp side (Layer 2) flips LF back to CR so
cmd.exe still sees a single Enter keystroke. No payload is lost — the
`\r` ↔ `\n` swap round-trips because the normalizer collapses runs.

Source: `src/term.lisp:405-412` (the `term.onData` replace and the
explanatory comment citing the 1011 crash), `src/term.lisp:428-431`.

---

## Layer 2: `%normalize-child-input`

`%normalize-child-input` (src/term.lisp:58-91) is the single
choke point for every byte that reaches the child's stdin. It does
three transforms in one pass:

1. **Drop code points greater than `#xFF`.** The child stream uses
   `:external-format :latin-1` (Layer 3), so anything outside 0x00-0xFF
   has no lossless representation. Surrogate halves that hunchensocket
   occasionally synthesizes from malformed UTF-8 get dropped the same
   way (regression lock: `normalize-child-input-drops-surrogate-like-code`).
2. **Translate LF (10) to CR (13).** Under ConPTY, cmd.exe treats only
   CR as the Enter key — bare LF is just a control byte it buffers.
   The browser sends LF because of the Layer 1 crash workaround, so the
   flip back happens here.
3. **Collapse runs of CR down to a single CR.** This is the `2a95c96`
   fix. Any call-site that terminates a line with CRLF, LFLF, or CRCR
   would otherwise emit two CRs. When a `set /p` (or any single-line
   reader) is live on the child, the extra CR silently answers it with
   empty input. The picker-inject bug was the first manifestation, but
   `.dispatch/inject-contract-audit.md` enumerates at least two more
   at-risk call-sites (the UI preset button and the e2e fixture). Making
   the normalizer idempotent kills the entire class at the choke point,
   so callers don't have to memorize which terminator the wire expects.

Contract guaranteed to downstream code: the output is a
`(simple-array (unsigned-byte 8))` where no run of CR bytes exceeds
length 1, and no byte exceeds `#xFF`. The array is built with
`:adjustable t` because `vector-push-extend` strictly requires an
adjustable array per CLHS — the pre-`2a95c96` code worked on SBCL only
by implementation quirk.

Source: `src/term.lisp:58-91`, `.dispatch/inject-contract-audit.md`.

---

## Layer 3: spawn-child stdio

`spawn-child` (src/proc.lisp:28-55) launches a subprocess with piped
stdin / stdout (stderr merged into stdout) and returns a `child-process`
struct holding the `uiop:process-info` and the two Lisp streams.

Two subtleties documented in `.dispatch/proc-element-type-audit.md` are
load-bearing here.

**`:element-type` is ignored.** `uiop:launch-program` forwards the key
to `sb-ext:run-program` with `:allow-other-keys t`, but `run-program`'s
lambda list does not declare `:element-type`, so the key is accepted
and silently dropped. Internally, `get-descriptor-for` on the `:stream`
case hardcodes `:element-type :default`, which resolves to `CHARACTER`
on SBCL. The previous code declared `'(unsigned-byte 8)` here and had a
docstring claiming a byte stream; neither was ever true at runtime.
Runtime verification via `/api/eval`: `(stream-element-type (child-process-stdin c))`
returns `CHARACTER`, not `(unsigned-byte 8)`. Commit `e5a19b7` drops the
declaration and rewrites the docstring to match reality.

**`:external-format :latin-1` is the actual fix.** Without it the stream
inherits `:default`, which on modern Windows SBCL is `:utf-8`. A single
CP932 or CP437 byte from cmd.exe would trip UTF-8 decoding and tear the
stdout pump — `%scrub-for-utf8` only cleans the outbound WS frame, not
the child stream read. Latin-1 is bijective over 0x00-0xFF, so no decode
can fail. This matters today only for non-ASCII output paths that haven't
been exercised, but it removes the entire decode-failure class rather
than leaving it latent.

**SBCL fd-stream bivalence.** Callers still use `read-byte` and
`write-sequence` on byte vectors. That is legal against SBCL's
`CHARACTER` fd-streams by implementation detail (not ANSI guarantee).
The docstring in `src/proc.lisp:29-46` records this contract so future
readers don't re-open the "why are we writing bytes to a char stream"
question.

Source: `src/proc.lisp:8-55`, `.dispatch/proc-element-type-audit.md`.

---

## Layer 4: conpty-bridge

Under bare piped stdio, cmd.exe (and anything it spawns) sees no TTY.
Interactive CLIs like `claude` detect that and refuse to start a REPL;
`set /p CHOICE="> "` echoes nothing because it's not a real console;
Enter is LF, not CR. That last point directly contradicts Layer 2's
LF-to-CR rewrite, so picker auto-inject used to write
`scripts\pick-agent.cmd` followed by CR bytes into cmd, which just
buffered them and never executed the script. No error surfaced — the
child was waiting on an Enter it would never recognize.

`%default-argv` (src/proc.lisp:18-26) prepends
`tools/conpty-bridge/conpty-bridge.exe` in front of `cmd.exe` whenever
the bridge binary is present:

    (list *conpty-bridge-path* "cmd.exe")

The bridge is a small Go program that spawns its argv under a real
Windows Pseudo Console (ConPTY) and shuttles stdin / stdout between
the Lisp pipes and the ConPTY master via a 1 KiB `io.Copy` loop
(tools/conpty-bridge/main.go:45-80, chosen over the default 32 KiB so
keystrokes reach cmd immediately). Externally the bridge still speaks
pipe protocol — Layer 3's streams are unchanged. Internally cmd.exe
sees full terminal semantics: CR is Enter, `set /p` echoes, `claude`
starts the REPL.

The pre-`de778f7` bug was that `%shell-argv` on Windows returned
`'("cmd.exe")` directly, bypassing `%default-argv` and therefore the
bridge wrap. The fix makes `%shell-argv` delegate to `%default-argv`,
which falls back to bare cmd.exe if the bridge binary is missing. Two
regression tests lock this:
`term-shell-argv-windows-uses-conpty-bridge-when-present` and
`term-shell-argv-windows-falls-back-to-cmd-when-bridge-missing`
(tests/term-tests.lisp:214-243).

Build: `cd tools/conpty-bridge && go build -o conpty-bridge.exe .`

Source: `src/proc.lisp:8-26` (bridge path + `%default-argv`),
`src/term.lisp:195-204` (`%shell-argv`), `tools/conpty-bridge/main.go`.

---

## Layer 5: picker auto-inject

When a client connects, `hunchensocket:client-connected` spawns the
child, starts the stdout pump thread, and fires a third worker thread
that sleeps 0.4s and then writes the picker command into the child's
stdin. The 0.4s delay lets cmd.exe finish drawing its banner first.

The picker line is built with a **single LF terminator**:

    (format nil "~a~c" (%agent-picker-command) #\Newline)

On Windows `%agent-picker-command` returns `"scripts\\pick-agent.cmd"`.
After `%normalize-child-input` the trailing LF becomes one CR — exactly
one Enter keystroke to cmd. Originally the code built the line with
`\r\n`, which normalize flipped to `\r\r`: the first CR fired the batch
file, and the second CR raced ahead and answered `set /p CHOICE="> "`
with an empty line before the user could press 1/2/3. `de778f7` fixed
the inject terminator, and `2a95c96` made the collapse unconditional so
any future caller that hard-codes CRLF is also safe.

Observability: the worker records three trace markers on the `:meta`
direction so a future silent failure surfaces in `/api/shell-trace`
instead of disappearing:

- `[picker-inject:enter]` — thread started, about to write
- `[picker-inject:wrote]` — write-sequence returned cleanly
- `[picker-inject:ERR <type> <msg>]` — captured by `handler-case`

The previous code used `ignore-errors`, which swallowed the exact bug
class this trace is designed to catch.

`*auto-pick-agent*` is `T` unless `DISABLE_AGENT_PICKER=1` in the
environment. Regression lock: `term-picker-enabled-by-default`
(tests/term-tests.lisp:131-139).

Source: `src/term.lisp:268-312` (client-connected + picker thread),
`src/term.lisp:260-266` (`%agent-picker-command`),
`scripts/pick-agent.cmd`.

---

## Debug observability

`/api/shell-trace` returns a JSON array of the most recent 100 frames
that flowed through `/ws/shell`, newest first. Each entry:

    { "ts": "2026-04-20T12:00:00Z",
      "dir": "in" | "out" | "meta",
      "bytes": <int>,
      "preview": "<ASCII-safe 80-char preview>" }

Directions:

- **in** — bytes written to the child stdin (Layer 2 output)
- **out** — bytes read from the child stdout
- **meta** — internal markers; currently only Layer 5's
  `[picker-inject:enter|wrote|ERR]` triple

The preview is ASCII-scrubbed (CR and LF rendered as space, sub-0x20 as
`.`, NIL as `.`) so the trace itself can't throw and crash the
recording thread — `%preview` at `src/term.lisp:138-156`.

Typical debugging walkthrough for a silent picker failure:

1. Open `/shell` in a browser.
2. `curl http://localhost:8090/api/shell-trace` within 1s of connect.
3. Expected prefix (newest first):
   `[picker-inject:wrote] / [picker-inject:enter] / <out: banner>`.
4. If `[picker-inject:enter]` is missing, the worker never ran
   (`DISABLE_AGENT_PICKER=1` set? `client-connected` threw before the
   `make-thread`?). If `[picker-inject:wrote]` is missing, `write-sequence`
   threw — look for the `[picker-inject:ERR ...]` marker.
5. If all three are present but the browser shows no picker menu, the
   bridge is probably absent — `/api/eval` `(child-process-process ...)`
   and check the argv.

Source: `src/term.lisp:123-193` (trace ring + handler), `src/term.lisp:289-308`
(meta markers inside picker-inject).

---

## Testing

Regression coverage for all three fix commits lives in
`tests/term-tests.lisp`. The UT2i/UT2j blocks (lines 141-361) are the
canonical reference:

- Layer 2 core contract — `normalize-child-input-*`
  (tests/term-tests.lisp:141-193). ASCII passthrough, LF→CR flip, CR
  preservation, out-of-latin-1 drop, lone surrogate drop.
- Layer 2 idempotency class-wide — `term-normalize-collapses-consecutive-crs`
  (tests/term-tests.lisp:339-361). Locks CRLF, LFLF, CRCR, and
  four-byte double-CRLF (paste scenario) all collapsing to one CR.
- Layer 4 routing — `term-shell-argv-windows-uses-conpty-bridge-when-present`,
  `term-shell-argv-windows-falls-back-to-cmd-when-bridge-missing`,
  `term-shell-argv-not-unconditional-cmd-on-windows`
  (tests/term-tests.lisp:214-261). The pre-fix literal `'("cmd.exe")`
  body is explicitly rejected.
- Layer 5 terminator — `term-picker-inject-line-ends-in-single-lf`,
  `term-picker-inject-normalized-ends-in-single-cr`,
  `term-picker-inject-terminator-is-one-byte-not-two`
  (tests/term-tests.lisp:266-333). The last one is the class-level
  lock that asserts LF, CR, CRLF, LFLF, and CRCR all produce
  byte-identical normalized output.

**Not covered by the suite:**

- End-to-end browser-to-claude REPL: there is no puppeteer test in
  CI. The only evidence is the manual verification noted in
  `de778f7`'s commit message (screenshot showing the Welcome card).
- Real ConPTY behavior: the bridge itself has Go tests
  (`tools/conpty-bridge/*_test.go`), but the combined Lisp → bridge →
  cmd.exe → claude path is manual-only. A `/api/eval` smoke test from
  a running server is the closest substitute.
- Non-ASCII child output: the latin-1 external format fix is currently
  exercised only by the absence of a regression — no test feeds a
  CP932 byte through the full pump.
- `inject-e2e-scenario.lisp:74` was changed from `\r\n` to `\n`
  (2a95c96) so it now exercises the picker-wire shape, but it does
  not assert the collapse itself; that job belongs to the unit tests
  above.

Run the suite with `scripts/run-tests.sh` (or `(asdf:test-system :photo-ai-lisp)`
from a running REPL). The 7 pre-existing `PIPELINE-INVOKE-VIA-CP-*`
failures are a CP-server-down artifact unrelated to this stack.

Source: `tests/term-tests.lisp:141-361`, `tests/inject-e2e-scenario.lisp:74`.

---

## Known issues

- **Port 8090 zombie socket.** On Windows, a previous SBCL run that
  died without cleaning up hunchentoot can leave the listening socket
  held long enough that the next `scripts/demo.sh` fails with
  `address in use`. There is no automatic cleanup in-tree; the
  operational workaround is `netstat -ano | findstr 8090` +
  `taskkill /F /PID <pid>`. Tracking this in-server would mean
  binding with `SO_REUSEADDR` and is orthogonal to the shell stack.
- **Windows locale mojibake.** Latin-1 decoding of the child stdout
  is bijective over bytes (Layer 3), which means non-ASCII output
  from cmd.exe (Japanese error messages under CP932, for example)
  reaches the browser as Mojibake rather than the intended glyphs.
  `%scrub-for-utf8` (src/term.lisp:206-223) only replaces unencodable
  code points with `?` — it does not transcode. A correct fix would
  decode the child stream as the active OEM code page and re-encode
  as UTF-8 on the WS send path. None of the three commits covered
  here addresses this; today's traffic is ASCII-only in practice.
- **`listen`-driven pump idle wait.** `%stdout-pump` (src/term.lisp:226-258)
  sleeps 20ms between `listen` checks. Under heavy output this shows
  up as a 20ms tail latency on the last chunk. A blocking `read-byte`
  would be cleaner but would require a second thread for cancellation
  on child exit. The current code is a deliberate simplicity trade-off.
- **Picker default timing.** The 0.4s sleep before picker inject is
  a hand-tuned constant — long enough for cmd's banner on a warm
  boot, not long enough on a cold boot with AV scanning cmd.exe.
  There is no feedback signal from the child that the banner finished
  printing, so longer is safer but more user-visible lag.

Source: `src/term.lisp:226-258` (pump), `src/term.lisp:206-223`
(`%scrub-for-utf8`), `src/term.lisp:285-308` (picker timing).
