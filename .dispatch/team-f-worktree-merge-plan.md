# Team F — worktree merge plan: `track-b/ansi-parser`

**Status:** planning doc only. Do **not** execute any of the commands below.
Main-thread / next-session decision required before any merge, archive, or prune.

## Decision path selected: **(a) merge candidate**

### Evidence

- `git worktree list`:
  - `C:/Users/yuuji/photo-ai-lisp-track-b` → `track-b/ansi-parser` @ `524b5d9`
- `git log main --oneline -1`: `0c2bed0 docs(shell): add 5-layer architecture reference…`
- `git merge-base main track-b/ansi-parser` → `4186410`
- `git log track-b/ansi-parser ^main --oneline | wc -l` → **20 commits** on track-b
  not in main (Phase 4 ANSI parser + Phase 5 screen/html/handlers, 267-check suite).
- `git diff --stat main...track-b/ansi-parser`:
  `19 files changed, 1991 insertions(+), 189 deletions(-)`.
- **Zero overlap on the feature files**: `src/ansi.lisp`, `src/sgr.lisp`,
  `src/screen.lisp`, `src/screen-events.lisp`, `src/screen-html.lisp`,
  `tests/ansi-tests.lisp`, `tests/screen-tests.lisp`,
  `tests/screen-scenario.lisp`, `tests/sgr-tests.lisp` **do not exist in main**
  (`git log main -- src/ansi.lisp …` → empty).

### Why merge (reasoning)

- track-b is a **disjoint feature track** (pure terminal emulator internals)
  landed on its own branch and then abandoned mid-integration because of a
  now-resolved ASDF-shadowing test regression (524b5d9 is the fix).
- The Phase 5 work is production-grade: **267 checks, 0 fail** per the
  track-b HANDOVER.md.
- Main has since moved to a ghostty-web / ConPTY-bridge approach for the
  user-facing terminal (see 0c2bed0, 2a95c96, 3fcdd6b, e48667f). The
  track-b screen emulator is **not made obsolete by that** — it is a
  Lisp-native renderer that could back future snapshot / scrollback /
  tested-screen features once plugged into the ws/shell pipeline.
- **Caveat (confidence check):** I cannot verify with certainty that current
  main does not depend on something that would break once `screen.lisp` etc.
  are introduced (package export collisions, ASDF load order). The merge
  plan below lists the exact friction points to inspect.

## Files that will conflict on merge

Flagged by `git diff --name-only main...track-b/ansi-parser`:

| File | Conflict shape | Resolution hint |
|------|----------------|-----------------|
| `photo-ai-lisp.asd` | track-b lists 8 src files (pkg, ansi, screen, sgr, screen-events, screen-html, agent, main). Main lists ~14 src files (agent, business-ui, case, control, cp-client, cp-protocol, live-repl, main, package, pipeline, pipeline-cp, presets, proc, term). | **Union** the `:components` list, keep `:serial t` load order so `screen.lisp` loads after `package.lisp` but before any consumer. Extend `:depends-on` only if track-b added deps (currently only `hunchentoot cl-who`, same as main). Mirror changes in `photo-ai-lisp/tests` component list. |
| `src/package.lisp` | Both sides export different symbol sets. No name collision observed (track-b exports `make-parser parser-feed … cell screen cursor apply-event screen->text screen->html parse-sgr-params`; main exports `photo-case *sessions* *skills* …`). | **Merge additively** — keep both export blocks. Re-scan for collisions by `grep -E "^\s*#:" src/package.lisp` after merge. |
| `src/main.lisp` | track-b size 27 lines, main size 102 lines — main's `main.lisp` has substantially more handlers. | **Prefer main's version entirely** unless track-b adds a specific entry point not present in main. Diff inspection required before keeping any track-b hunk. |
| `HANDOVER.md` | track-b's HANDOVER is dated 2026-04-18 and describes Phase 5 wrap-up + regression. Main's HANDOFF.md was refreshed 2026-04-20 (e48667f). Different filenames (HANDOVER vs HANDOFF) — actually **not** the same file on main. | **Prefer main's `HANDOFF.md`**; move track-b's `HANDOVER.md` to `docs/archive/handover-2026-04-18.md` if historical context is wanted, else drop. |
| `LESSONS.md` | track-b adds +37 lines. Main may or may not have LESSONS.md today. | Check with `ls LESSONS.md`. If absent, accept track-b version. If present, 3-way merge needed. |
| `README.md` | track-b adds +22 lines (Phase 5 overview). | Cherry-pick the Phase 5 section into main's README if still accurate post-merge; otherwise drop. |
| `.github/workflows/test.yml` | track-b adds `track-b/ansi-parser` to the CI branch filter. | After merge into main, this entry becomes obsolete — drop it. |
| `.gitignore` | track-b adds 2 lines. | Inspect hunks; keep if generally useful, drop if track-b-specific. |
| `docs/3bst-reference.md` | Exists only on track-b (new 258-line file). Main's `docs/` has `shell-architecture.md`, `tier-breakdown.md`, etc. — no overlap. | **Accept track-b version as-is.** |
| `HANDLER_OWNER_BRIEF.md` | Exists only on track-b (new 96-line file). | **Do not carry forward** — it's a brief for the 2026-04-18 session, stale post-merge. Move to `docs/archive/` or drop. |

## Purely additive files (zero conflict, just add)

- `src/ansi.lisp` (143 lines)
- `src/sgr.lisp` (120 lines)
- `src/screen.lisp` (115 lines)
- `src/screen-events.lisp` (152 lines)
- `src/screen-html.lisp` (75 lines)
- `tests/ansi-tests.lisp` (86 lines)
- `tests/sgr-tests.lisp` (171 lines)
- `tests/screen-tests.lisp` (482 lines)
- `tests/screen-scenario.lisp` (15 lines)

## Proposed merge procedure (do not execute yet)

Assumes main-thread human has ack'd the plan.

```bash
# 1. Safety snapshot
git switch main
git pull --ff-only  # make sure we're at origin/main
git tag pre-merge-track-b-ansi-parser
git push fork pre-merge-track-b-ansi-parser  # tag lives on own fork only

# 2. Feature branch off main
git switch -c merge/track-b-ansi-parser

# 3. Merge with --no-commit so we can surgically resolve
git merge --no-ff --no-commit track-b/ansi-parser

# 4. Resolve file-by-file per the table above
#    - For *.asd / package.lisp: manual union edit
#    - For main.lisp: git checkout --ours src/main.lisp
#    - For HANDOVER.md / HANDLER_OWNER_BRIEF.md / README.md: case-by-case
#    - For all src/screen*.lisp, src/ansi.lisp, src/sgr.lisp, tests/*: take as-is

# 5. Local verify
sbcl --non-interactive \
     --eval "(require 'asdf)" \
     --eval "(asdf:test-system :photo-ai-lisp/tests)"
# Expected: main-side tests AND track-b screen/sgr/ansi tests all pass,
# total check count ≈ (main tests) + ~267 screen-side.

# 6. Commit and open PR against own fork
git commit -m "Merge track-b/ansi-parser: Phase 4/5 ANSI parser + screen emulator"
git push fork merge/track-b-ansi-parser
gh pr create --repo YuujiKamura/photo-ai-lisp ...

# 7. Only after PR green — cleanup:
git worktree remove C:/Users/yuuji/photo-ai-lisp-track-b
git branch -d track-b/ansi-parser      # safe delete (merged)
git branch -d track-b/5e4a-sgr-parse   # merged into track-b/ansi-parser already
```

## Risks / open questions for human review

1. **`src/agent.lisp` — different file on each side?** Both branches list
   `agent.lisp` in their ASD. On track-b it is a new file introduced alongside
   screen work; on main it is a pre-existing file with different content.
   `git diff main...track-b/ansi-parser -- src/agent.lisp` must be inspected
   before merge. This is **the single most likely silent-break file** and was
   not in the summary 19-file list above because the diff tool may have
   tracked it through a rename. Treat with care.
2. **ASDF `:serial t` load order:** The `package.lisp` is first in both.
   Post-merge, `ansi.lisp` / `screen.lisp` / `sgr.lisp` / `screen-events.lisp`
   / `screen-html.lisp` should load early (they're pure). Anything that
   references the new symbols must be ordered after.
3. **Test-suite regression guardrail:** the 267-check baseline in track-b
   HANDOVER.md should be demanded post-merge. Any number below
   `(current-main-count + 267 - 1)` means something dropped silently.
4. **track-b/5e4a-sgr-parse** is an ancestor of track-b/ansi-parser (merged
   in e5e1b6e). It can be pruned after the main merge, not before.

## Alternative: skip (b) archive and (c) prune

Neither applies. The branch is **not** stale experimental work — it is
feature-complete with passing tests and is referenced by main's ecosystem
(see 0af0237 `ci: allow tests on track-b/ansi-parser`). Archiving would
lose Phase 5; pruning would delete it.

If the human operator disagrees and decides the ghostty-web approach
supersedes the Lisp-native screen emulator entirely, the prune path is:

```bash
# NOT RECOMMENDED — destroys Phase 5 work
git worktree remove C:/Users/yuuji/photo-ai-lisp-track-b
git branch -D track-b/ansi-parser
git branch -D track-b/5e4a-sgr-parse
git push fork :track-b/ansi-parser   # delete from own fork
git push fork :track-b/5e4a-sgr-parse
```

## Not touched by this plan

- `.claude/worktrees/agent-a03e3777` (locked) — out of scope
- `.claude/worktrees/agent-a10cb0d3` (locked) — out of scope
- `photo-ai-lisp-split` @ `feat/atom-17.5-split` — out of scope, different track
