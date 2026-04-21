# Tier 2 Fixed Agent Choice

**Decision:** The Tier 2 fixed agent is `claude --model sonnet`, launched
inside a ghostty-win session managed by deckpilot.

## Why `claude` over `gemini` / `codex`

- **Interactive REPL fidelity.** The demo streams CP `INPUT` into a live pane
  and expects output back in the iframe. `claude`'s terminal UI is the
  protocol the ghostty-web pipe, CP driver, and auto-approvals were built
  against.
- **Stateful conversation.** Tier 2 shows a user typing in one pane and
  reading a coherent multi-turn reply in another. `claude` keeps session
  state natively; `gemini` and `codex` CLIs suit one-shot / headless / batch
  work and need extra glue to look live.
- **Primary dev-loop agent.** `scripts/pick-agent.cmd` already lists claude
  as option 1, and deckpilot launcher patterns default to it. Reusing it
  keeps Tier 2 on the best-exercised rail.
- **Gemini / Codex kept for their strength.** Both remain available for
  batch roles (mechanical refactor, test-stub generation). Tier 2 is the
  *visible demo* role, which is not their best fit.

## Why Sonnet over Opus

Opus has a weekly quota cap and is reserved for main-thread reasoning and
final judgement. Sonnet comfortably sustains 8 hours of continuous demo at
this throughput, leaving Opus available for architectural decisions outside
the demo loop.

## Launcher command

```
claude --model sonnet
```

This is the command string spawned inside the ghostty-win session that
deckpilot creates on boot. `scripts/pick-agent.cmd` (option 1 = `claude`)
confirms the same binary; Tier 2 pins the model to Sonnet explicitly instead
of relying on the CLI default.

## Wiring into `scripts/boot-hub.lisp` (T2.h pivot)

**Change 2026-04-21:** The demo used to spawn a deckpilot ghostty-win
session and try to route CP INPUT frames back to it. That never actually
round-tripped (see "Tier 2 Known Gap" in BACKLOG.md — `*demo-cp-client*`
stayed nil, `/ws/shell` was a different shell than the deckpilot one,
and INPUT always hit the `:mock-client` path). T2.h replaces that model
with a direct spawn: the iframe's `/ws/shell` child *is* the agent.

Set the agent command once in the environment, then launch the hub in
demo mode:

```
set PHOTO_AI_LISP_DEMO_AGENT=claude --dangerously-skip-permissions --model sonnet
sbcl --script scripts/boot-hub.lisp --demo
```

On `/ws/shell` client-connect, `%demo-agent-argv` (in `src/term.lisp`)
reads that env var, splits it on spaces, and spawns the command as the
WebSocket's child process. The picker auto-inject (`pick-agent.cmd`) is
skipped because the child *is* the agent. `input-bridge-handler` (T2.b)
detects the same env var and, instead of sending CP frames, calls
`shell-broadcast-input` to write the command into every connected
`/ws/shell` child's stdin — which is the same child the iframe is
rendering. One flow, one child.

If `PHOTO_AI_LISP_DEMO_AGENT` is unset, the iframe shows the pick-agent
menu as before and the INPUT button falls through to the legacy CP path
(mostly useful for testing the non-demo codepath).

`spawn-demo-agent` and `parse-demo-session-name` in `scripts/boot-hub.lisp`
and `src/cp-ui-bridge.lisp` are kept as callable legacy helpers (dead
code in the current boot path; removed from `run-demo`) so downstream
scripts that import them keep loading.

Without `--demo` the script runs the T1.c smoke (connect → LIST →
disconnect → exit 0), which CI depends on and must not be broken.
