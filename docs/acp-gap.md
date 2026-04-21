# ACP gap analysis (G12.a)

status: draft; decision deferred to G12.b
refs: #30 (parent), #27 (roadmap A)

## 1. Purpose

photo-ai-lisp has a home-grown Control Plane (CP) protocol: a tiny set of
JSON verbs (`INPUT`, `SHOW`, `STATE`, `LIST`) carried over a single WebSocket
from the browser to the Common Lisp hub, then fanned out to headless
`claude`/`codex`/`gemini` agents. G1.a (merged in `a8c484d`) wrapped that
flat payload in a Jupyter-style 5-part envelope (`header` / `parent_header`
/ `metadata` / `content` / `buffers`).

A parallel industry effort — the **Agent Client Protocol (ACP)**, published
at <https://agentclientprotocol.com> and implemented by Zed, Jupyter AI and
several commercial hosts — aims to standardize the same shape of traffic
we invented: "editor/host UI ↔ coding agent", with session lifecycle,
prompt turns, filesystem access, and terminal spawning.

This document lines up ACP's surface against our CP surface so that G12.b
can make a single, evidence-based call: adopt ACP (A), stay bespoke (B),
or expose ACP as a thin facade (C). The ACP spec page at
`/protocol` resolved cleanly during research, so §2 is based on the
canonical source (not a fallback to Zed's Rust impl).

## 2. ACP surface summary

Grouped by bucket. Direction is c2a (client→agent) or a2c (agent→client).

### Lifecycle (c2a, request/response)
- `initialize` — negotiate protocol version and exchange capabilities.
- `authenticate` — authenticate against the agent when required.

### Session (mixed)
- `session/new` — create a new conversation session (c2a, req/resp).
- `session/load` — resume an existing session (c2a, req/resp, optional).
- `session/prompt` — send a user prompt turn to the agent (c2a, req/resp).
- `session/set_mode` — switch operating modes (c2a, req/resp, optional).
- `session/cancel` — cancel ongoing work in a session (c2a, notification).
- `session/update` — progress / tool-call / plan / command / mode-change stream from agent (a2c, notification).
- `session/request_permission` — agent asks the host to authorise a tool call (a2c, req/resp).

### File system (a2c, request/response, optional)
- `fs/read_text_file` — agent reads a host file.
- `fs/write_text_file` — agent writes a host file.

### Terminal (a2c, request/response, optional)
- `terminal/create` — allocate a terminal on the host.
- `terminal/output` — fetch buffered stdout plus exit status.
- `terminal/wait_for_exit` — block until the terminal process exits.
- `terminal/kill` — terminate the running command without releasing the handle.
- `terminal/release` — free the terminal resource.

### Notification bucket (overlay, not a separate namespace)
- `session/update` (see above) is the only pure agent→client notification.
- `session/cancel` is the only pure client→agent notification.
- All other verbs are request/response.
- Custom methods prefixed with `_` are permitted for extensions.

Total: **14 methods** across 4 buckets (2 lifecycle + 7 session + 2 fs + 5 terminal). This count is the baseline for §4 cross-check.

## 3. Current CP surface

All four verbs live in `src/cp-protocol.lisp`. Every generator wraps its
payload in the G1.a 5-part envelope, and `cp-parse-response` accepts
either 5-part or legacy flat replies.

| CP verb | generator (Lisp symbol) | purpose | carries user input? |
|---------|-------------------------|---------|---------------------|
| `INPUT` | `make-cp-input` | send a prompt/keystroke to the agent (base64 in `content.msg`) | yes |
| `SHOW`  | `make-cp-tail` | pull the last `n` lines from the agent's scrollback buffer | no |
| `STATE` | `make-cp-state` | poll the agent's `active`/`idle` state | no |
| `LIST`  | `make-cp-list-tabs` | enumerate running sessions on the hub | no |

There is no `AUTH`, no `NEW` for session creation (sessions appear
out-of-band when deckpilot launches a tab), no explicit `CANCEL`, no
filesystem verb, and no separate terminal lifecycle verb beyond the
implicit one baked into `INPUT`/`SHOW`.

## 4. Mapping

LoC estimates assume G1.a envelope infra is reusable and that "adopt"
means adding a new `make-cp-<verb>` plus a hub-side handler plus a
`cp-client.lisp` helper. Numbers are whole-function counts, not diff lines.

| ACP method | CP equivalent | match quality | LoC to add if adopted | notes |
|------------|---------------|---------------|-----------------------|-------|
| `initialize` | (none) | NONE | ~40 | Trivial: return static capability struct. Mostly schema. |
| `authenticate` | (none) | NONE | ~30 | No-op for localhost; stub returning `ok`. |
| `session/new` | (implicit; sessions spawn via deckpilot) | PARTIAL | ~80 | Needs to call deckpilot to spin up an agent tab and return a session id. |
| `session/load` | `LIST` gives you existing ids; no resume | PARTIAL | ~40 | Map to "attach to existing deckpilot tab". |
| `session/prompt` | `INPUT` | EXACT | ~60 | 1:1. Re-encode base64 payload as ACP's `content` array. |
| `session/set_mode` | (none) | NONE | ~30 | Optional in ACP, skip unless we add modes. |
| `session/cancel` | (none — today relies on Ctrl-C via INPUT) | PARTIAL | ~50 | Need a real cancel path to the agent subprocess. |
| `session/update` | `SHOW` (pull) | PARTIAL | ~120 | Biggest semantic shift: ACP is push-stream, CP is pull-tail. Requires hub to fan stdout chunks into notifications in real time. |
| `session/request_permission` | (none) | NONE | ~60 | Would gate tool use through the browser; currently agents self-authorise. |
| `fs/read_text_file` | (none) | NONE | ~40 | Trivial wrapper over `uiop:read-file-string`. |
| `fs/write_text_file` | (none) | NONE | ~40 | Trivial wrapper; must guard against writing outside project root. |
| `terminal/create` | (implicit in deckpilot) | PARTIAL | ~80 | Could map to "spawn ghostty-web tab". |
| `terminal/output` | `SHOW` | EXACT | ~30 | Already a tail of N lines; only the envelope differs. |
| `terminal/wait_for_exit` | (none) | NONE | ~60 | Blocking RPC; the hub would need a one-shot promise keyed to msg_id. |
| `terminal/kill` | (none; relies on process-level `kill`) | NONE | ~40 | Plumb a kill down to deckpilot. |
| `terminal/release` | (none) | NONE | ~30 | Free a terminal handle without killing the process. |

Rough total if we adopt everything: **~830 LoC** of Lisp, spread across
`cp-protocol.lisp`, `cp-ui-bridge.lisp`, and a new handler for each verb.
That is substantially more than the G1.a envelope work (a few hundred LoC)
but still a weekend, not a month.

## 5. Reverse mapping (CP verbs with no ACP equivalent)

- `STATE` — "is the agent busy or idle?" In ACP, busy/idle is reported
  *inside* `session/update` notifications (execution state changes piggy-back
  on the stream). **Drop if we migrate** — replace with `session/update`
  execution_state.
- `LIST` — enumerates running sessions on the hub. ACP has no
  session-enumeration verb: the host is assumed to own the list. In our
  architecture the browser *is* the host, so we'd either keep `LIST` as a
  custom `_list` method or track sessions client-side. **Keep**, under a
  `_list` extension prefix (ACP reserves `_`-prefixed names for this).

Every other CP verb has an ACP counterpart, so the delta is small: 2 of our
4 verbs have no direct ACP home.

## 6. Recommendation

### (A) Adopt ACP as the sole external protocol; CP becomes internal only
Cost: ~830 LoC new Lisp, plus refactoring iframe JS to speak ACP over WS
instead of the current flat frames. The CP-to-ACP semantic shift in
`session/update` (push instead of pull) means rewriting
`cp-ui-bridge.lisp`'s output fan-out, not just adding verbs.
Benefit: instant interop with Zed, Jupyter AI, and the growing ACP
ecosystem; deckpilot shim could be replaced by any ACP-compliant agent
launcher; free schema validation and test fixtures from upstream.
Blockers: ACP assumes the *agent* speaks the protocol; today our agents
are `claude`/`codex`/`gemini` CLIs that speak nothing. We'd still need a
per-agent adapter — we just move bespoke code from the hub to an ACP
shim. Net LoC change is not as favourable as it looks.

### (B) Keep CP; do not adopt ACP
Cost: continued isolation; every new host UI needs to learn our 4 verbs;
we carry the maintenance burden of the envelope alone.
Benefit: velocity. CP is ~200 LoC today and covers everything Tier 1–3
dogfood needs. ACP's terminal/fs verbs duplicate what we already solve
via deckpilot + direct filesystem access in Lisp. No downstream pressure
yet: no one is asking us to connect to Zed.
Blockers: none in the short term. Risk is a future "we should have
adopted the standard" regret if/when a second host (VS Code plugin, TUI,
mobile) needs to drive photo-ai-lisp.

### (C) Hybrid: ACP server facade on top of CP
Cost: ~400–500 LoC for a translation layer (session/prompt → INPUT,
terminal/output → SHOW, etc.), plus ongoing drift maintenance when ACP
evolves. Two protocols to debug when something breaks.
Benefit: existing CP clients keep working unchanged; ACP-speaking hosts
(Zed, Jupyter AI) can connect without us rewriting the browser iframe.
Maintenance burden: moderate — the facade is pure translation and can be
test-cased against upstream ACP conformance fixtures once those exist.

**Recommendation: (C) — ship the ACP facade, keep CP as the internal
wire.** CP is cheap, works today, and dropping it (option A) forces a
browser-side rewrite we do not need; staying closed (option B) leaves
zero optionality the day a second host matters. A facade is the only
option that preserves current velocity *and* buys interop when it's
asked for.

## 7. Open questions

1. Does Zed's ACP implementation actually support our use case of
   streaming long-running terminal output, or is `terminal/output` a
   pull API (like our `SHOW`) and thus equally polling-based? If pull,
   our "ACP is push, CP is pull" framing in §4 is wrong for that verb.
2. Is there a public ACP conformance test suite or JSON Schema we can
   run the facade against, or are we validating by hand-written fixtures?
3. Does ACP permit multiple concurrent sessions on one WS connection, or
   is the connection itself session-scoped? Our hub multiplexes many
   sessions over one WS; a 1:1 model would force us to open N sockets.
4. How does ACP handle reconnection / msg_id replay? G1.a added
   `msg_id` + `parent_header`; if ACP has a different replay story we
   need to reconcile before the facade lands.
5. Does `session/request_permission` fit deckpilot's auto-approval
   model, or does it assume a human-in-the-loop gate we do not want?
6. MCP overlap: is `fs/read_text_file` / `fs/write_text_file` in ACP
   redundant with an MCP server exposing the same filesystem? If agents
   already get filesystem via MCP, we can skip those two ACP verbs.
7. What is the expected transport? ACP is spec'd over JSON-RPC, but the
   transport (stdio vs WebSocket vs TCP) affects our facade — the spec
   page did not enumerate transport bindings and this needs confirmation
   from Zed source or upstream.

No ACP method in §2 was unclear; all 14 are described from the spec page
without fallback to Zed source. Flag for G12.b: re-confirm
`terminal/wait_for_exit` semantics (blocking vs long-poll) since the
upstream page phrases it as "wait" without a clear timeout contract.
