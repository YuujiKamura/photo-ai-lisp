# Tier 1 (Wire up) — verification

**Verdict: PASS** — 2026-04-20

The CP client on photo-ai-lisp successfully round-trips JSON commands with the
deckpilot `/ws` endpoint. Issue #19 Tier 1 acceptance criteria are met.

## Environment

- deckpilot: `main` at `c8056a8` (WS endpoint union implementation, Issue #27
  merged). Running daemon bound to `127.0.0.1:8080` listening on `/ws`.
- photo-ai-lisp: `main` at `50d376c` (JSON response parser + `wait-for-completion`
  landed via `d775a5e`; `.gitignore` updated at `50d376c`).
- SBCL 2.6.3 at `C:/Users/yuuji/SBCLLocal/PFiles/Steel Bank Common Lisp/sbcl.exe`.
- Live deckpilot sessions at test time: 11 (mix of active / dead / stalled
  Ghostty WinUI3 windows).

## Smoke script

`scripts/tier-1-smoke.lisp` was added. It is strictly client-side: it calls
`connect-cp`, `send-cp-command`, and `wait-for-completion`, then exits. It
never opens a listening socket.

Run:
```
sbcl --non-interactive --load scripts/tier-1-smoke.lisp
```

## Observed output

```
SMOKE: system loaded
SMOKE CONNECT: :OK
SMOKE LIST: (:CMD "LIST" :OK T :ERROR NIL :DATA #(<11 session hash-tables>)
             :STATUS NIL :MODE NIL :MESSAGE NIL)
SMOKE STATE-NONEXISTENT: (:CMD "STATE" :OK NIL
                          :ERROR "session not found: nonexistent" :DATA NIL
                          :STATUS NIL :MODE NIL :MESSAGE NIL)
SMOKE WAIT-TIMEOUT: NIL
SMOKE-OK
```

## Checklist

- [x] WebSocket upgrade and persistent connection (`connect-cp`)
- [x] JSON request serialization (`make-cp-list-tabs`, `make-cp-state`)
- [x] JSON response parsing into plist with `:ok` `:error` `:data` `:status`
      fields (`%parse-json-response` via shasht)
- [x] Success path: `LIST` returns `:ok t` with `:data` populated
- [x] Error path: unknown session returns `:ok nil` with `:error` string
- [x] Polling: `wait-for-completion` returns `NIL` on timeout without looping
      forever

## Known caveat

The daemon currently listening on `127.0.0.1:8080` is the build that was
running before the `main` merge of `fix/issue-27-merge-ws-bridges`. The
response shape test succeeded because the old `daemon/ws.go` already emitted
`{"ok":..., "error":..., "data":...}` compatible with the new parser — this
was by design (the merge preserved the union of both shapes). A fresh build
and restart is deferred so that the existing Ghostty WinUI3 sessions are not
killed; exercising the post-merge daemon is a follow-up once the user is
ready to bring sessions down.

## Next

Tier 2 (Minimal vertical slice) — render a business-ui case view with a live
ghostty-web iframe on one pane and a Lisp-hub-driven CP action on another,
reflected back in the terminal pane.

Issue #19 remains open; the Tier 1 checkbox in that issue's definition-of-done
is satisfied.
