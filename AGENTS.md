# Agent instructions (human + AI)

Before touching code, read `REQUIREMENTS.md`. It is the single source of
truth. Everything below reinforces it.

## Non-negotiables

1. **Map every change to `REQUIREMENTS.md`.** Before opening a file,
   identify which numbered section (§1 vision, §3 field, §5 flow, §6
   rule) your change implements. If nothing matches, **stop and ask**.
   Do not guess.

2. **No scope expansion without sign-off.** If an elegant-looking
   refactor or "while we're here" cleanup is not in `REQUIREMENTS.md`,
   it is not work to do. Open an issue and wait for a human decision.

3. **Tests come with code.** No function ships without a test. No
   "I'll add tests in a follow-up." Reuse the canonical test invocation
   documented in `tests/COVERAGE.md`.

4. **Working screen beats status text.** For any UI-touching change,
   the evidence of completion is a screenshot (or live smoke output),
   not prose. See `demo/` for the pattern.

5. **Silent execution.** Do not narrate "now I'll do X, then Y". Do the
   work, then file one end-of-turn summary.

6. **External actions require explicit approval.** No `gh pr create`,
   no `gh issue create`, no `git push` to branches outside your own,
   no public repo disclosures, unless the human asks in that session.

7. **Do not touch `REQUIREMENTS.md` without approval.** If you think
   something is missing, propose it in an issue or a message. Do not
   edit the SSOT from inside an agent task.

## Failure mode this file exists to prevent

When the human says "build a UI", agents tend to produce:

- a landing page
- a REPL route that was not asked for
- a fake-data test suite for an imagined API
- three framings of the README in one afternoon
- a VT100 emulator from scratch in the implementation language
- an elaborate orchestrator with invented CLI flags

Every one of those has happened in this repo's history (see
`LESSONS.md`). Re-reading `REQUIREMENTS.md` before each task is the
countermeasure.

## When in doubt

Stop. Ask. A two-sentence clarification from the human is cheaper than
an afternoon of branch churn.
