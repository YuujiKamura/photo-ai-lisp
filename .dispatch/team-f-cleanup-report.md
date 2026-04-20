# Team F — cleanup report

**Session date:** 2026-04-20
**Scope:** planning only — no worktree / branch / filesystem mutations were
executed. Three plan docs produced; all mutating operations are gated behind
main-thread human approval.

## 1. Worktree determination

| Worktree | Branch | Verdict |
|----------|--------|---------|
| `C:/Users/yuuji/photo-ai-lisp-track-b` | `track-b/ansi-parser` @ `524b5d9` | **(a) merge candidate** |
| `C:/Users/yuuji/photo-ai-lisp-split` | `feat/atom-17.5-split` @ `ec06092` | **out of scope** (brief only mentions track-b) |
| `.claude/worktrees/agent-a03e3777` | `worktree-agent-a03e3777` (locked) | **out of scope** (locked) |
| `.claude/worktrees/agent-a10cb0d3` | `worktree-agent-a10cb0d3` (locked) | **out of scope** (locked) |

**Primary finding — `track-b/ansi-parser`:**

- 20 commits ahead of the `4186410` merge-base with main; main has ~30
  commits not in track-b.
- +1991 / −189 lines across 19 files. Roughly 1300 of the +1991 are
  pure-addition feature files (`src/ansi.lisp`, `src/sgr.lisp`,
  `src/screen.lisp`, `src/screen-events.lisp`, `src/screen-html.lisp`,
  matching tests) that **do not exist on main at all**.
- Phase 5 work is feature-complete and green (267 checks / 0 fail per the
  track-b `HANDOVER.md`). The ASDF-shadowing regression that blocked
  integration was fixed in the tip commit `524b5d9`.
- Conflict surface on merge is narrow and tractable:
  `photo-ai-lisp.asd` (union components), `src/package.lisp` (union
  exports), `src/main.lisp` (prefer main), plus doc-level files
  (`HANDOVER.md`, `LESSONS.md`, `README.md`, `.github/workflows/test.yml`,
  `.gitignore`). Full per-file strategy is in
  **`team-f-worktree-merge-plan.md`**.

**Confidence caveat (per brief §4 — "推定しかできない場合は human 判断待ち"):**
I did not confirm whether `src/agent.lisp` differs materially between the
two sides. The merge plan explicitly flags it as "single most likely
silent-break file — inspect before merge."

**Not chosen:** (b) archive — would lose working Phase 5 code; (c) prune —
same. Both paths are documented in the merge plan as fallbacks if the
operator concludes the ghostty-web approach fully supersedes the
Lisp-native screen emulator.

## 2. `.dispatch/` classification summary

84 total files, ~656 KB (PNGs ~135 KB — below the 10 MB threshold so no
separate image-archive subdir proposed).

| Bucket | Count | Action |
|--------|-------|--------|
| **A. Active** (current-session briefs + templates) | 14 + `templates/` | Keep in root |
| **B. Archive** (landed-work briefs, PNGs, monitor logs) | 62 | Move to `.dispatch/archive/2026-04/` |
| **C. Stale** (pid files, captured stdout, runtime state) | 7 | Delete after script-inspection |

Detailed file list and move commands are in **`team-f-dispatch-plan.md`**.

## 3. Recommended next actions (priority order)

1. **Operator decision on track-b merge** — the merge plan is ready to
   execute. If yes, the operator runs the commands in
   `team-f-worktree-merge-plan.md` §"Proposed merge procedure" from a
   **main-thread** session (not a team subagent). Tests must green post-merge
   against both the main-side suite and the ~267-check screen/sgr/ansi suite.
2. **Operator decision on `.dispatch/` reorg** — low risk, mechanical.
   `team-f-dispatch-plan.md` §"Proposed procedure" can be applied in one
   shell session. Verify that `monitor-*.sh` scripts have no reusable value
   before the `rm`.
3. **Answer the session-boundary question** — are the `team-[a-e]` briefs
   still active, or was this a wrap-up session? If wrap-up, bucket A shrinks
   to `team-f-*` + `templates/` + recent reports, and the remaining
   team-* briefs move to archive.
4. **Optional — `.gitignore` amendment for tracked archive** (out of Team
   F's file scope). If the operator wants `.dispatch/archive/**` committed
   as history, `.gitignore` must be edited to re-include it. Current brief
   forbids `.gitignore` edits, so this is deferred.

## 4. Completion criteria (from brief)

- [x] `team-f-worktree-merge-plan.md` written (path (a) chosen)
- [x] `team-f-dispatch-plan.md` written
- [x] `team-f-cleanup-report.md` written (this file)
- [x] Zero mutations to `src/`, `tests/`, `docs/`, `static/`, `scripts/`,
      `tools/`, `HANDOFF.md`, `.gitignore`, `photo-ai-lisp.asd`
- [x] Zero `git worktree remove` / `git branch -D` / `git merge` /
      `git rebase` / `rm` against worktrees, branches, or `.dispatch/`
- [x] No push to upstream; no `--no-verify`

## 5. Files produced

```
.dispatch/team-f-worktree-merge-plan.md
.dispatch/team-f-dispatch-plan.md
.dispatch/team-f-cleanup-report.md
```

Plan-only; test count and code paths unchanged.
