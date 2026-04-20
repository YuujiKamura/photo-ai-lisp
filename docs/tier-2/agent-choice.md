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

## Wiring into `scripts/boot-hub.lisp`

On startup, `scripts/boot-hub.lisp` asks deckpilot to spawn exactly one
ghostty-win session whose child process is `claude --model sonnet`, then
stores the returned session id in `*demo-session-id*` for
`pipeline-cp:send-input` to target.
