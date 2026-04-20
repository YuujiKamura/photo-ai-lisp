# Tier 1/2/3 breakdown — Issue #19

Purpose: concrete per-tier design so each atom in `BACKLOG.md` Track T
has a reviewable spec to work against. This file is paired with the
Track T atoms; atom IDs here match IDs in `BACKLOG.md`.

Non-goals (inherited from Issue #19):
- Screen buffer in Lisp (Phase 5) — frozen behind the verdict.
- Tool intercept / claude `tool_use` parsing (Phase 7) — frozen.
- Multi-agent session management — Tier 3+, not Tier 2.
- Public deployment, auth, multi-user — out of scope.

---

## Tier 1 — Wire up

### Relationship to current state

- Atom 17.1 landed the CP protocol encoder/decoder (`src/cp-protocol.lisp`).
- Atom 17.2 landed the CP client using `websocket-driver` (`src/cp-client.lisp`).
- Atom 17.3 landed the pipeline-CP bridge (`src/pipeline-cp.lisp`) with
  `INPUT` dispatch + completion polling.
- Atom 17.4 (The Purge) removed all direct process spawning from
  `src/term.lisp` and `src/agent.lisp`. Lisp is now purely a CP client.
- Atom 17.5 (feat/atom-17.5-iframe, WIP) points the `business-ui` iframe
  at `*ghostty-web-url*` so the terminal pane is owned by ghostty-web.
- deckpilot Issue #27 is adding the matching `/ws` server endpoint.

Tier 1 is the handshake **between those two halves**: prove that a
running `cp-client` can complete a full request/response cycle against
a running deckpilot `/ws`.

### Boot procedure

1. Start ghostty-web daemon (external, already running convention).
2. Start deckpilot with `/ws` enabled on `127.0.0.1:8080/ws`
   (blocked on deckpilot Issue #27 landing).
3. `sbcl --script scripts/boot-hub.lisp`
   - loads the ASDF system,
   - connects `cp-client` to `ws://127.0.0.1:8080/ws`,
   - issues a `STATE` probe,
   - exits 0 on green, non-zero on any unhandled condition.

### Required daemons

| Component | Port / Path | Owner |
|-----------|-------------|-------|
| ghostty-web | TBD (known port, not hardcoded) | external |
| deckpilot `/ws` | `ws://127.0.0.1:8080/ws` | deckpilot #27 |
| photo-ai-lisp hub | stdout / log file | this repo |

### Verification log example (T1.b target)

```
# docs/tier-1/cp-roundtrip.log (expected shape)
[2026-04-20T09:00:00Z] connect ws://127.0.0.1:8080/ws → OK
[2026-04-20T09:00:00Z] send    {"verb":"STATE"}
[2026-04-20T09:00:00Z] recv    {"ok":true,"state":"idle"}
[2026-04-20T09:00:00Z] send    {"verb":"LIST"}
[2026-04-20T09:00:00Z] recv    {"ok":true,"sessions":[]}
[2026-04-20T09:00:00Z] send    {"verb":"INPUT","session":"s1","data":"echo hi\n"}
[2026-04-20T09:00:00Z] recv    {"ok":true}
[2026-04-20T09:00:00Z] send    {"verb":"SHOW","session":"s1"}
[2026-04-20T09:00:00Z] recv    {"ok":true,"text":"...hi..."}
[2026-04-20T09:00:00Z] disconnect OK
```

Exact verb names track `src/cp-protocol.lisp` — if the protocol drifts,
update this example rather than the source.

---

## Tier 2 — Minimal vertical slice

### UI composition (one page)

```
+---- browser: GET /cases/:id -----------------------------------+
|                                                                |
|  [case header]   case-id · title                               |
|                                                                |
|  [form POST]     [ run-demo-command ]  ← T2.b button           |
|                                                                |
|  +------------ iframe src=*ghostty-web-url* ----------------+  |
|  |                                                          |  |
|  |    live ghostty-web terminal pane                        |  |
|  |    (rendered by ghostty-web, not by Lisp)                |  |
|  |                                                          |  |
|  +----------------------------------------------------------+  |
|                                                                |
+----------------------------------------------------------------+
```

One page, one iframe, one button, one fixed agent session. Nothing else.

### Data flow

```
     +---------+                                             +-----------+
     | browser |                                             | ghostty-  |
     +----+----+                                             |   web     |
          |                                                  +-----+-----+
   GET    |  POST /cases/:id/input                                 ^
  page    |  (button press)                                        |
          v                                                        | stdout
     +----+--------------+   INPUT (CP/JSON)   +---------------+   | frames
     |  photo-ai-lisp    |-------------------->|  deckpilot    |---+
     |  business-ui      |                     |  /ws          |
     |  + cp-client      |<--------------------|  (session)    |
     |  + pipeline-cp    |   reply / broadcast +------+--------+
     +-------------------+                            |
                                                      | spawn/attach
                                                      v
                                               +------+--------+
                                               | fixed agent   |
                                               | (claude -p)   |
                                               +---------------+
```

Key invariants:
- Lisp **never** owns a PTY. All process ownership lives in deckpilot.
- The iframe points at ghostty-web, **not** at the Lisp hub.
- The only Lisp→browser channel is the HTTP response to the POST; the
  terminal output reaches the browser via ghostty-web's own pipe.

### Fixed agent selection

Recommendation: **one `claude -p` session managed by deckpilot**, stored
as `*demo-session-id*` at boot.

Rationale:
- `claude -p` has the richest tool-use surface and is the agent we plan
  to harden against in Phase 7 (post-verdict). Using it in Tier 2 means
  the dogfood verdict reflects the target workflow, not a proxy.
- Single session eliminates the scheduling/multi-session matrix; those
  problems belong to Tier 3+ and would false-negative the verdict if
  mixed in now.
- `claude -p` is CLI-scriptable and already boots cleanly under
  deckpilot, so zero new integration work is needed for T2.

Explicitly **not** chosen for T2:
- gemini-cli: less mature tool-use, less signal on the KEEP/ARCHIVE axis.
- codex: fine agent, but its usage pattern overlaps with `claude -p`
  without adding independent evidence for the verdict.

### Scope locks for Tier 2

- No Phase 5 screen buffer. ghostty-web renders.
- No Phase 6f broadcast to multiple clients. One browser tab, one agent.
- No Phase 7 tool intercept. Agent runs as a plain PTY child of deckpilot.
- No refactor of `src/term.lisp` beyond what T2.a requires.

---

## Tier 3 — Dogfood week

### Candidate real-task comparison

| Candidate | Pros | Cons | Verdict |
|-----------|------|------|---------|
| **photo-import pipeline via Lisp hub** | already an existing use case (this repo's raison d'être); runs repeatedly during normal work; easy to count invocations; touches the `defpipeline` engine we already shipped | requires existing photo corpus on the machine running dogfood | **recommended** |
| multi-agent session (claude + gemini + codex) | stresses more of the stack | Issue #19 explicitly defers multi-session to Tier 3+; adopting it during the verdict-week conflates UX signal with scheduling-bug signal | rejected |
| other terminal-driven daily work | flexible | not repeatable; one-off tasks give no usage-count signal | rejected as primary; acceptable as secondary fill |

Primary: photo-import pipeline.
Secondary (fills idle slots): README edits, lint runs, git operations —
anything normally done in a terminal that the hub could dispatch.

### Usage-log format

One command per line, tab-separated:

```
<iso8601-utc-timestamp>\t<verb>\t<session-id>\t<payload-bytes>
```

Example:
```
2026-04-21T09:17:32Z	INPUT	s1	42
2026-04-21T09:17:33Z	SHOW	s1	0
2026-04-21T09:18:05Z	INPUT	s1	117
```

Verb set is closed (see `docs/tier-3/usage-log-format.md` / atom T3.b):
`INPUT | SHOW | STATE | LIST | BOOT | SHUTDOWN`. Unknown verbs are a
bug, not a free-form extension.

Byte count is the UTF-8 length of the JSON `data` field for `INPUT`,
0 otherwise.

### 1-week plan (Mon–Fri)

| Day | Activity | Checkpoint file |
|-----|----------|-----------------|
| Mon | Fresh `make demo`; drive the day's photo-import run through the hub. Capture usage.log. | `docs/tier-3/checkpoints/mon.md` |
| Tue | Continue photo-import via hub; log any frustration moment. | `docs/tier-3/checkpoints/tue.md` |
| Wed | Mid-week pulse: tally hub vs CLI command ratio from Mon+Tue. | `docs/tier-3/checkpoints/wed.md` |
| Thu | Stress: intentionally use the hub for an adjacent task (e.g. lint). | `docs/tier-3/checkpoints/thu.md` |
| Fri | Compute final ratios; fill `docs/tier-3-verdict.md`. | `docs/tier-3/checkpoints/fri.md` |

Each checkpoint file uses the T3.c template and records:
- hub-driven command count (grep usage.log for that date)
- CLI-driven command count (manual count, +1 per terminal command run
  outside the hub — on honor system; imperfect but countable)
- frustration events (free-text, one line each)
- blockers / daemons that crashed
- minutes spent on the real task

### KEEP/ARCHIVE criteria (pre-registered, see T3.d)

Verdict rule — all thresholds must be pre-committed **before** dogfood
week begins, not tuned to the result:

```
hub_ratio = sum(hub_commands) / (sum(hub_commands) + sum(cli_commands))

KEEP   iff hub_ratio >= 0.40
       AND mean(daily_frustration_count) <= 5
       AND no-day had hub unavailable for > 30 min

ARCHIVE otherwise
```

Rationale:
- 0.40 is a deliberately modest bar — the Lisp hub only needs to
  displace a meaningful minority of terminal use to justify Phase 5/7.
- A frustration ceiling prevents "technically used a lot, hated every
  minute of it" from passing.
- An availability floor prevents a collapsed daemon from masquerading
  as disuse.

### Either-outcome exits

- **KEEP**: invest in Phase 5 (screen buffer) and Phase 7 (tool
  intercept). Unfreeze those atoms in `BACKLOG.md` via atom `T.KEEP.next`.
- **ARCHIVE**: freeze the Lisp hub as-is; keep deckpilot `/ws` as a
  permanent public API; annotate `BACKLOG.md` via `T.ARCHIVE.next`;
  move on.

Both outcomes are successful exits. The failure mode is **no verdict**
— remaining in the ambiguous middle state where atoms keep landing
without anyone committing to the artifact.
