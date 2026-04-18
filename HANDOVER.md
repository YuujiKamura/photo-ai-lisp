# Handover — 2026-04-18 evening

This file is the starting point for the next session. Read `LESSONS.md`
first, then this one.

## Current state

- `main` is reset to skeleton state (commit `c494ad2`).
  - `src/package.lisp`, `src/main.lisp` (Hunchentoot hello handler only)
  - `photo-ai-lisp.asd`, `LICENSE`, `README.md`, `docs/index.html`, `.gitignore`
  - `LESSONS.md` documents what drifted and should not be repeated
- `archive/2026-04-18-drift-snapshot` holds the full drift-era code
  (agent embed, tools, pipeline, CI workflow, 41 tests). Treat it as a
  cherry-pick source, not as reference architecture.

## Target direction

Lisp is the orchestrator. The browser terminal is the existing
ghostty-web binary, talked to over its CP protocol. The agent CLI
(claude / gemini / codex) is a subprocess whose stdin/stdout the Lisp
server brokers. Skills (`~/.agents/skills/photo-*/`) and the Rust
exporter binary stay as external processes; Lisp only invokes them
after their real CLI shape is probed.

```
Browser
  └─ ghostty-web (xterm rendering)
        ↕ CP protocol
   photo-ai-lisp (Hunchentoot)
        ↕ uiop:launch-program
    agent CLI (claude / gemini / codex)
        ↕ tool call
    PhotoAISkills (Python) + Rust binary
```

## Do-next, in order

Each step ends with a committed, pushed change on `main`, and no
subsequent step starts until the previous one is green.

### Step A: probe real skill CLI shape

Before any Lisp wrapper is written, run each skill manually and
record the actual CLI contract.

- For each directory under `~/.agents/skills/photo-*/`, find the
  scripts directory (not always `scripts/`, not always `.py`). Run
  the entry point with `--help` and `-h`, capture stdout / stderr.
- Write `docs/skill-cli.md` recording, per skill: command, required
  args, optional flags, output channel (stdout JSON vs file), exit
  codes, any environment assumptions.
- Do not invent flags. If a skill has no `--help`, document the
  unknown state.

Commit: `docs: probe actual PhotoAISkills CLI shape`.

### Step B: bring back CI

Cherry-pick `.github/workflows/test.yml` from
`archive/2026-04-18-drift-snapshot`, adapted to the current
minimal codebase. Expect zero tests to run for now; the job should
still succeed (load the system and exit 0).

Commit: `ci: restore GitHub Actions workflow for main`.

### Step C: minimal agent subprocess

Port `src/agent.lisp` from the archive branch, trimmed to just
`*agent-command*`, `*agent-args*`, `start-agent`, `stop-agent`,
`agent-alive-p`, and `agent-send`. Drop the restart monitor for now.
Add one scenario test (not unit test) that:

- spawns the configured agent command (default: real `claude`)
- sends a trivial prompt
- asserts a non-empty response within 30 seconds

If `claude` is not installed the test skips. Do not use `cat` as a
fake agent — that proved useless last time.

Commit: `feat: minimal agent subprocess lifecycle with scenario test`.

### Step D: ghostty-web embedding

Figure out how to embed ghostty-web in a page served by Hunchentoot,
using its CP protocol for the bidirectional pipe. This step is
research-heavy:

- Read ghostty-web's CP protocol docs / source
  (`project_ghostty_web_cp.md` in memory points to commit 7439e5d)
- Stand up ghostty-web locally and confirm you can render a terminal
  driven by a trivial Lisp-managed subprocess (e.g. `echo hi`)
- Only then wire the agent subprocess through

No commit until a browser actually renders a live terminal driven by
a Lisp-side process. Screenshot that browser, land it in `docs/`.

Commit: `feat: embed ghostty-web terminal backed by Lisp CP broker`.

### Step E: skill tool plumbing

With the real CLI shapes from Step A, implement `src/skills.lisp`
fresh. One function per skill, with argument names matching the
actual CLI. No generic `run-skill` — the generic version encouraged
guessing. Write a scenario test per skill that runs against real
files in a temp directory.

Commit: `feat: typed skill wrappers backed by probed CLI contracts`.

### Step F: agent tools

Expose the skill wrappers as tools to the agent. Format depends on
which agent backend is used; keep it adapter-shaped so switching
backends is a single module change.

Commit: `feat: agent tool bridge for skill invocation`.

## Non-goals for this pass

- REPL front page (the drift-era `/eval` endpoint)
- Upload / Scan / Manifest / Pipeline HTTP routes beyond what ghostty-web itself shows
- Unit tests for imagined APIs
- Landing page copy revisions before the architecture is solid
- Multi-agent dispatcher pipelines. One Claude session does the
  work top to bottom; nothing gets dispatched to a child agent.
- `cat`-based fake agents

## Operating constraints

- Do not invent CLI flags for external tools.
- Do not write a Lisp wrapper before calling the underlying binary
  by hand.
- Run the system at every step. `(ql:quickload :photo-ai-lisp)` and
  the scenario test must stay green.
- After each commit, `git push origin main` and verify GitHub
  Actions turns green (once Step B is done).
- If you introduce a new HTTP route, exercise it in a browser
  before the commit.
- If you get stuck for more than 20 minutes, stop and write what is
  unknown into `HANDOVER.md` before doing anything else.

## Environment reminders

- SBCL at `C:/Users/yuuji/SBCLLocal/PFiles/Steel Bank Common Lisp/sbcl.exe`
- Quicklisp at `~/quicklisp/`, project symlinked at
  `~/quicklisp/local-projects/photo-ai-lisp/`
- Rust exporter at
  `C:/Users/yuuji/exporters/target/release/photo-ai-rust.exe`
- Skills at `~/.agents/skills/photo-*/`
- Windows + Git Bash shell. Use `uiop:os-windows-p` for any
  platform-sensitive branch.

Good luck.
