# Lessons from the 2026-04-18 drift

This project briefly expanded into a multi-route web app with a REPL page, a chat UI wired to an embedded agent, five skill-backed tool endpoints, twelve unit-test files, a full pipeline orchestrator, and an elaborated landing page — all in one day, driven by a pipeline of agents communicating through GitHub issues.

The result was visually running, tests passed, and the commit history looked productive. Actually trying to use the thing surfaced a pile of drift: tool schemas invented by AI, pipeline steps calling skills with guessed CLI flags, a fake-agent test that only proved a pipe echoes bytes, a chat UI whose example chips were never exercised against a real model, and a README describing three successive framings of the same goal.

That full state is preserved in branch `archive/2026-04-18-drift-snapshot` for reference. `main` is reset to the initial skeleton so the next iteration can pick back only what is justified by actual use.

## What drifted, and why

- **Multi-layer dispatch** (main Claude → dispatcher Claude → worker Claude → Codex). Each layer re-interpreted requirements. Decisions near the leaves turned into code that the top layer never validated.
- **Tool schemas were guessed.** `run-skill` assumed `~/.agents/skills/<name>/scripts/<name>.py` and that scripts print JSON to stdout. PhotoAISkills do not all follow that shape.
- **Pipeline arguments were fabricated** (`--scope`, `--input`, `--output-dir`) to keep the orchestrator compiling, even when the actual skill CLI did not accept them. One step wrote `{"skipped":true}` as a hack so the next step could proceed.
- **Tests validated the scaffold, not the behavior.** 85 FiveAM assertions passed, but none exercised a real skill, a real agent, or an end-to-end user scenario.
- **UI surface grew faster than usage.** Routes `/`, `/photos`, `/upload`, `/scan`, `/manifest`, `/pipeline`, `/chat`, `/eval`, `/repl` existed without anyone opening a browser and actually using them against real data.
- **README pivoted mid-flight.** Viaweb-styled → REPL-front-page → agent-chat, all in one afternoon, leaving descriptive text disconnected from what the code did.

## What is worth picking back

Items that survived reality testing and are worth re-introducing deliberately:

- **S-expression HTML templating with `cl-who`** — concise and fine.
- **`(setf hunchentoot:*dispatch-table* (list (create-prefix-dispatcher "/path" 'handler-symbol)))`** — must use the symbol form, not `#'handler-symbol`, so redefining the handler at the REPL actually takes effect on the next request.
- **`:shadowing-import-from` or explicit `hunchentoot:` prefix** when defining a local `start`/`stop` — the `:use #:hunchentoot` + `(defun start ...)` pattern silently shadows `hunchentoot:start` and made `(start *acceptor*)` recurse into the wrong function.
- **GitHub Actions CI on ubuntu-latest** with `apt install sbcl`, Quicklisp bootstrap, project symlinked into `~/quicklisp/local-projects/`, and a `fiveam:results-status` gate. Reliable, cacheable, cheap.
- **`uiop:os-windows-p` branching for `python`/`python3` and for `.exe` / no-ext binary paths.** Cross-platform work needs this from the start.

## What to not repeat

- Do not create handlers you are not about to exercise in a browser within the same session.
- Do not add a skill-calling wrapper before running the underlying skill by hand and capturing its real stdout/stderr/exit-code.
- Do not write unit tests for imagined APIs; write a scenario test that runs the happy path end-to-end first.
- Do not let AI executors invent CLI flags. If the skill's arguments are unknown, add a probe step that runs `<skill> --help` and stores the result before proceeding.
- Do not let landing-page copy lead the architecture. The README should describe what the code does, not what the framing should be.
- Do not spawn a new worker agent to close a thinking backlog. Thinking backlog is a signal; give it context or take over.

## Next iteration shape (sketch)

The direction, not a commitment:

- Keep Lisp for orchestration and tool provision only.
- Terminal emulator responsibilities go to an embedded ghostty-web instance, talked to over the existing CP protocol.
- Agent subprocess lifecycle can be salvaged from `archive/2026-04-18-drift-snapshot:src/agent.lisp` once the rest of the architecture is settled.
- Skills stay as-is under `~/.agents/skills/photo-*/`. The Lisp side only invokes them after probing their real CLI shape.

This file exists so the next pass does not repeat today.

## 2026-04-18 night — the Phase 5 "267 -> 49 checks" regression

During Phase 5 wrap-up the suite silently dropped from 267 checks to
49. `SGR-TESTS` and `SCREEN-SCENARIO` never registered and
`SCREEN-TESTS` stopped after the third `(test ...)`. No warnings,
no errors, exit 0. The earlier handover hypothesized FASL staleness
and `tests/package.lisp` forward-decls. Both were wrong.

**Root cause.** `~/quicklisp/local-projects/` contained three sibling
directories (`Cu8rnsaC/`, `photo-ai-lisp/`, `photo-ai-lisp-track-b/`)
that were orphan `cp -r` snapshots of the worktree. All three held a
`photo-ai-lisp.asd` with out-of-date `:components` (missing `sgr`,
`screen-events`, `screen-html`, `screen-scenario`, `sgr-tests`). ASDF
resolved the system from whichever `.asd` came first in
`system-index.txt` — `Cu8rnsaC` — so the live worktree's real `.asd`
was shadowed. Only the files that happened to exist in that snapshot
compiled, and only the first 3 deftests survived because the
snapshot's `screen-tests.lisp` was a smaller older copy of the file.

**Fix (permanent).**

1. Renamed the three orphan `.asd` files to
   `photo-ai-lisp.asd.stale-orphan-20260418` so ASDF can no longer
   discover them.
2. Added `(pushnew #P"C:/Users/yuuji/photo-ai-lisp-track-b/"
   asdf:*central-registry* :test #'equal)` to `~/.sbclrc` so the live
   worktree is the canonical location.
3. Verified `(asdf:test-system :photo-ai-lisp/tests)` now runs 267
   checks, 0 fail, including `SCREEN-SCENARIO-HELLO-WORLD-VIA-PARSER`.

**Takeaway.** "Stale FASL" and "broken loader" are last-resort
hypotheses. When the symptom is "some tests silently missing", first
confirm which `.asd` ASDF is actually loading — a `(asdf:system-source-file
:foo)` probe or a `trace asdf:load-asd` surfaces the real path in one
call. Duplicate `.asd` files under ASDF search roots shadow silently,
with no warning.
