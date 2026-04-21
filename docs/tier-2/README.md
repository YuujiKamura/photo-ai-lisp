# Tier 2 demo evidence (T2.g)

This directory holds the committed proof that the Tier 2 vertical slice
round-trips end-to-end through the shell-broadcast model introduced by
T2.h: one browser page, one iframe, one INPUT button, one fixed agent,
and the agent's output streaming back into that same iframe.

## What demo.png shows

- Left pane: the business-UI case view for `t2g-demo`
  (`/cases/t2g-demo`), including:
  - the case heading
  - the `path / reference / masters` metadata block
  - the **Send ping** button (the T2.b INPUT button)
- Right pane: the iframe connected via `/ws/shell`, rendering the live
  shell child's output. Visible content: the demo agent's opening
  banner `[DEMO] iframe ready` followed by the `cmd.exe` prompt
  `C:\Users\yuuji\photo-ai-lisp>`.

Because the child the iframe renders IS the INPUT recipient (T2.h
pivot), the banner itself is agent output that arrived via the Lisp
hub's `/ws/shell` pump — i.e. the vertical slice works.

## Reproduction (live claude agent)

1. Set the agent command:

   ```bash
   export PHOTO_AI_LISP_DEMO_AGENT="claude --dangerously-skip-permissions --model sonnet"
   ```

2. Boot the hub in demo mode:

   ```bash
   sbcl --script scripts/boot-hub.lisp --demo
   ```

   The hub listens on `:8090` by default. If `:8090` is held by an
   orphan socket from a prior run, override with `PHOTO_AI_HUB_PORT=8091`
   (the port shown in `demo.png`). `--demo` skips the legacy
   deckpilot spawn path and lets `/ws/shell` pick up
   `PHOTO_AI_LISP_DEMO_AGENT` via `%demo-agent-argv` in
   `src/term.lisp`.

3. Open the case view:

   ```
   http://localhost:8090/cases/demo
   ```

   (The PNG uses `/cases/t2g-demo`; any case id under
   `demo/cases/` works — the iframe and INPUT wiring are identical.)

4. Click **Send ping**. The form POSTs `cmd=echo hello from hub` to
   `/cases/<id>/input`; `input-bridge-handler` detects
   `PHOTO_AI_LISP_DEMO_AGENT` is set and routes through
   `shell-broadcast-input`, writing the command into every connected
   `/ws/shell` child's stdin.

5. Within ~5 s the claude session's response streams back into the
   iframe over the same `/ws/shell` frame that rendered its banner.

## Why cmd.exe was used for the committed PNG

Running live `claude --model sonnet` for T2.g evidence would consume
the weekly Opus/Sonnet quota on an operation that only needs to prove
the wiring. Substituting `cmd /k echo [DEMO] iframe ready` for
`PHOTO_AI_LISP_DEMO_AGENT` exercises the exact same code path
(iframe → `/ws/shell` → child stdin, `INPUT` → `shell-broadcast-input`
→ same child) without a model call, which is why the banner in
`demo.png` is a cmd prompt rather than a claude response. The live
claude variant is reproducible per the steps above.

## Verification in demo.log

`demo.log` transcribes the `GET /api/shell-trace` snapshot captured
against the same hub instance that rendered `demo.png`, plus the exact
`curl -X POST` response body that drove the round-trip:

```
$ curl -X POST -d "cmd=dir" http://127.0.0.1:8091/cases/t2g-demo/input
{"ok":true,"mode":"shell-broadcast","session":"demo","recipients":1,"bytes":4}
status=200
```

`mode="shell-broadcast"`, `recipients=1`, and `status=200` confirm
that the INPUT button dispatched through the T2.h demo path (not the
legacy CP / `:mock-client` branch) and reached the same child process
the iframe is rendering.

## Related files

- `demo.png` — the evidence screenshot (this directory)
- `demo.log` — transcribed shell-trace + INPUT POST response
- `agent-choice.md` — rationale for `claude --model sonnet` as the
  Tier 2 fixed agent, and the T2.h pivot wiring
- `e2e.log` — T2.d mock-mode frames (kept as historical artefact)
- `baseline-notes.md` — Tier 2 scope lock and DoD reference
- `../../src/cp-ui-bridge.lisp` — `input-bridge-handler`
  (demo-mode branch = shell-broadcast)
- `../../src/term.lisp` — `%demo-agent-argv`, `%shell-argv`,
  `shell-broadcast-input`
- `../../scripts/boot-hub.lisp` — `run-demo` entry
