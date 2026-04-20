# Team F — `.dispatch/` organization plan

**Status:** planning doc only. Do **not** move, archive, or delete anything.
Main-thread / next-session operator must ack before running the commands below.

## Scope

84 files currently in `.dispatch/`. `.gitignore` already ignores the directory
(`!templates/` kept). Total size **~656 KB**, of which PNG screenshots are
**~135 KB** (well under the 10 MB threshold, so no separate `.dispatch/archive/img/`
split is needed — regular `archive/` is fine).

## Classification

### A. Active — keep in `.dispatch/` root (do not touch)

Current session briefs that other teams may still be consuming:

- `team1-cleanup-brief.md`, `team1-cleanup-report.md`
- `team2-cp-tests-brief.md`
- `team-a-cp-retry-brief.md`
- `team-b-bridge-integration-brief.md`
- `team-c-shell-architecture-docs-brief.md`, `team-c-docs-report.md`
- `team-d-cp-pipeline-proper-brief.md`
- `team-e-puppeteer-e2e-brief.md`
- `team-f-worktree-dispatch-cleanup-brief.md` (Team F input)
- `team-f-worktree-merge-plan.md` (Team F output)
- `team-f-dispatch-plan.md` (this file)
- `team-f-cleanup-report.md` (Team F final report)
- `templates/` (explicit gitignore exception — leave alone)

**Count:** 14 files + `templates/` dir.

### B. Archive — move to `.dispatch/archive/2026-04/`

Briefs/reports that are linked to landed commits or past completed sessions.
Value: historical context when reading `git log` months from now.

**Codex case/session stream (pre–`04a62b6` era work that landed on main):**
- `codex-01-case-from-directory.md`
- `codex-02-find-case.md`
- `codex-03-lookup-session.md`
- `codex-04-register-session.md`
- `codex-05-clear-session.md`
- `codex-06-build-case-env.md`
- `codex-07-parse-shell-case-query.md`
- `codex-08-api-session-handler.md`
- `codex-09-spawn-child-directory-env.md`
- `codex-10-shell-case-wiring.md`

**Codex business-ui stream (landed in business-ui.lisp + tests):**
- `codex-business-ui-01-scan-cases.md`
- `codex-business-ui-02-case-id.md`
- `codex-business-ui-03-case-from-id.md`
- `codex-business-ui-04-list-cases-handler.md`
- `codex-business-ui-05-case-view-handler.md`
- `codex-business-ui-06-home-handler.md`
- `codex-business-ui-07-route-wiring.md`

**Codex pipeline-DSL stream (landed in pipeline.lisp + tests):**
- `codex-pipeline-01-find-skill.md`
- `codex-pipeline-02-register-skill.md`
- `codex-pipeline-03-unregister-skill.md`
- `codex-pipeline-04-find-pipeline.md`
- `codex-pipeline-05-defpipeline.md`
- `codex-pipeline-06-run-pipeline-core.md`
- `codex-pipeline-07-run-halt-on-failure.md`
- `codex-pipeline-08-run-unknown-skill.md`

**Plan / policy stream (stubs that were followed to completion):**
- `plan-01-case-clos.md`, `policy-01-case-clos.md`
- `plan-02-pipeline-dsl.md`, `policy-02-pipeline-dsl.md`
- `plan-04-business-ui-skeleton.md`, `policy-04-business-ui-skeleton.md`

**Gemini (landed, dated work):**
- `gemini-5304-manager-role.md`
- `gemini-atom-17.5-integration.md` (→ `feat/atom-17.5-iframe` / `feat/atom-17.5-split`)
- `gemini-atom-17.5-split.md`
- `gemini-conpty-debug.md` (→ conpty-bridge landed)
- `gemini-cp-client-json-parse.md` (→ `cp-client.lisp` landed)
- `gemini-dispatch-playbook.md` (→ `docs/dispatch-playbook.md`)
- `gemini-tier-1-wire-up-verify.md` (→ `cp-protocol.lisp` + tier-1 docs)
- `gemini-tier-2-baseline.md` (→ `cp-client.lisp` + `docs/tier-breakdown.md`)

**Issue-linked briefs (gh issues still reachable):**
- `claude-issue-19-task-breakdown.md`
- `issue-15-codex-brief.md`
- `issue-16-brief.md`
- `issue-17-cp-integration.md`
- `issue-housekeeping-brief.md`

**Audit briefs (audit outcomes now reflected in src/):**
- `inject-contract-audit.md` (→ `/api/inject` landed, `ba1a914`)
- `proc-element-type-audit.md` (→ `e5a19b7`)

**Task A/B/C/D series (landed, reports complete):**
- `task-b-lisp-io-to-bridge.md` (→ ConPTY bridge)
- `task-b2-narrow.md`, `task-b2-verify.md` (→ `80a22fa` byte-vector normalization)
- `task-c-verify-80a22fa.md`
- `task-c2.md`, `task-c2-report.md`
- `task-d-restart-and-verify.md`, `task-d-report.md`

**Screenshots (visual proof for landed tasks):**
- `task-b-result.png`, `task-b2-error.png`, `task-b2-result.png`, `task-b2-result-view.png`
- `task-d-after1.png`, `task-d-noinput.png`, `task-d-result.png`

**Monitor session artifacts (historical run logs):**
- `monitor-brief.md`, `monitor-log.md`

**Misc (complete, standalone):**
- `deckpilot-time-awareness-brief.md`

**Count:** 62 files.

### C. Stale — delete

Ephemeral runtime artifacts with no documentation value:

- `monitor-loop.out` — captured stdout from one-off loop
- `monitor-loop.sh` — one-off bash wrapper (reusable? **inspect first**)
- `monitor-waitidle.out` — captured stdout
- `monitor-waitidle.sh` — one-off bash wrapper (**inspect first**)
- `monitor-state.json` — runtime state snapshot
- `tier-2-sbcl.pid` — stale SBCL pid file (the process is long gone)
- `atom01-test.log` — one-shot test output

**Count:** 7 files.

**Inspection note:** `monitor-loop.sh` and `monitor-waitidle.sh` may contain
reusable patterns; before deleting, grep them for anything worth promoting
into `scripts/` or a skill. If yes, move; if no, delete.

## Proposed procedure (do not execute yet)

```bash
cd C:/Users/yuuji/photo-ai-lisp

# 1. Create archive dir
mkdir -p .dispatch/archive/2026-04

# 2. Move archive bucket (62 files)
#    Using explicit patterns so nothing in bucket A or C gets swept in:
mv .dispatch/codex-*.md                       .dispatch/archive/2026-04/
mv .dispatch/plan-0{1,2,4}-*.md               .dispatch/archive/2026-04/
mv .dispatch/policy-0{1,2,4}-*.md             .dispatch/archive/2026-04/
mv .dispatch/gemini-*.md                      .dispatch/archive/2026-04/
mv .dispatch/claude-issue-19-task-breakdown.md .dispatch/archive/2026-04/
mv .dispatch/issue-{15,16,17}-*.md            .dispatch/archive/2026-04/
mv .dispatch/issue-housekeeping-brief.md      .dispatch/archive/2026-04/
mv .dispatch/inject-contract-audit.md         .dispatch/archive/2026-04/
mv .dispatch/proc-element-type-audit.md       .dispatch/archive/2026-04/
mv .dispatch/task-b-lisp-io-to-bridge.md      .dispatch/archive/2026-04/
mv .dispatch/task-b2-*.md                     .dispatch/archive/2026-04/
mv .dispatch/task-c-verify-80a22fa.md         .dispatch/archive/2026-04/
mv .dispatch/task-c2*.md                      .dispatch/archive/2026-04/
mv .dispatch/task-d-*.md                      .dispatch/archive/2026-04/
mv .dispatch/task-*.png                       .dispatch/archive/2026-04/
mv .dispatch/monitor-brief.md                 .dispatch/archive/2026-04/
mv .dispatch/monitor-log.md                   .dispatch/archive/2026-04/
mv .dispatch/deckpilot-time-awareness-brief.md .dispatch/archive/2026-04/

# 3. Inspect-then-delete stale bucket
cat .dispatch/monitor-loop.sh     # decide: scripts/ or rm
cat .dispatch/monitor-waitidle.sh # decide: scripts/ or rm
rm .dispatch/monitor-loop.out
rm .dispatch/monitor-loop.sh       # only after inspection
rm .dispatch/monitor-waitidle.out
rm .dispatch/monitor-waitidle.sh   # only after inspection
rm .dispatch/monitor-state.json
rm .dispatch/tier-2-sbcl.pid
rm .dispatch/atom01-test.log

# 4. Verify
ls .dispatch/                      # should show ~14 files + templates/ + archive/
ls .dispatch/archive/2026-04/      # should show 62 files
```

## Why this split (reasoning)

- **Keep bucket A live** because other teams in the current session may still
  `Read` those files; moving them would break active cross-team references.
- **Archive bucket B** rather than delete because each file is tied to a
  merged commit — useful when archaeologically tracing "why was this
  designed this way?" 6 months from now. `git log` alone loses the brief
  content once the brief is out of the working tree.
- **Delete bucket C** because they are process residue (PID files, captured
  stdout, runtime state). They have no narrative value.

## Risks / open questions

1. **Active-bucket definition depends on session membership.** If the
   operator is starting a brand-new session, every `team1-*`, `team-a-*`,
   `team-b-*` … brief can actually be moved to archive too. Re-ask the
   operator: "is this the same session as teams 1/A/B/C/D/E, or fresh?"
2. **`templates/*.md`** stays untouched regardless — it's an explicit
   `.gitignore` exception and used by the dispatch playbook.
3. **`monitor-*.sh` inspection** before delete is mandatory — they may be
   the scaffolding a later session wants to re-use.
4. `.dispatch/archive/` itself is not gitignored differently from the root;
   it remains ignored by `.dispatch/*`. If the operator wants archive to be
   **tracked** for long-term value, `.gitignore` needs:
   ```
   .dispatch/*
   !.dispatch/templates/
   !.dispatch/templates/*.md
   !.dispatch/archive/
   !.dispatch/archive/**
   ```
   — but this is **out of Team F's scope** (`.gitignore` untouchable per brief).
