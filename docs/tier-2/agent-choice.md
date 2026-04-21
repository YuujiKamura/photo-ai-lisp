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

Pass `--demo` to enter demo mode:

```
sbcl --script scripts/boot-hub.lisp --demo
```

On startup the script calls `spawn-demo-agent`, which runs:

```
deckpilot launch sonnet "hub ready, awaiting first input" --cwd <repo-root>
```

deckpilot expands `sonnet` to `claude --dangerously-skip-permissions --model sonnet`,
creates a ghostty-win session, and returns the session name (e.g. `ghostty-12345`)
on stdout.  `parse-demo-session-name` extracts the last non-empty line and sets
`photo-ai-lisp:*demo-session-id*`, which `input-bridge-handler` (T2.b) targets
for subsequent CP INPUT frames.

Without `--demo` the script runs the T1.c smoke (connect → LIST → disconnect →
exit 0), which CI depends on and must not be broken.
