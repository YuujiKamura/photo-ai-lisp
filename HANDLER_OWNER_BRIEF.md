# Handler Owner Brief (38136)

Dispatched 2026-04-18 evening. 37928 owns the spine; you own the parallel
handlers + polish. Goal is to reach Phase 5 completion tonight — the
"できた" milestone where fed ANSI bytes render through `(screen->text)`
and `(screen->html)` end-to-end.

## Your tasks, in order

### 1. 5e.4a — pure SGR param parser (start NOW, no deps)

- New file: `src/sgr.lisp`
- `(parse-sgr-params params-list) -> plist`
- Spec (ECMA-48 / xterm):
  - `0` -> `(:reset t)`
  - `1` -> `(:bold t)`; `22` -> `(:bold :reset)`
  - `4` -> `(:underline t)`; `24` -> `(:underline :reset)`
  - `7` -> `(:reverse t)`; `27` -> `(:reverse :reset)`
  - `30-37` -> `(:fg N)` where N in 0..7
  - `40-47` -> `(:bg N)` where N in 0..7
  - `90-97` -> `(:fg N :bright t)` (or choose encoding and document it)
  - `100-107` -> `(:bg N :bright t)`
  - `38 5 N` -> `(:fg N)` 256-color
  - `48 5 N` -> `(:bg N)` 256-color
  - `39` -> `(:fg :default)`
  - `49` -> `(:bg :default)`
  - multiple modifiers in one sequence combine
  - empty list -> treated as `(0)` per spec
- Pure function. No screen, no cursor, no side effects.
- Unit tests: 15+ assertions in `tests/sgr-tests.lisp`. Cover each
  branch plus edge cases (empty, unknown param, combined).
- Commit: `feat(screen): 5e.4a — pure SGR param parser`.

### 2. Wait for 37928 to land 5e.1 (dispatcher skeleton + :print)

Check `git log` periodically. `5e.1` adds `(apply-event screen event)`
and wires `(:type :print :char C)`. Once that's in, the dispatcher
is extensible and you can add more handlers.

### 3. 5e.2 — apply `:cursor-move` and `:cursor-position`

Add branches to the `apply-event` dispatch. Relative moves for
`:cursor-move` (A/B/C/D), absolute for `:cursor-position`. Clamp to
grid bounds. Unit tests per direction + out-of-bounds clamp.

Commit: `feat(screen): 5e.2 — cursor-move and cursor-position`.

### 4. 5e.3 — apply `:erase-display` and `:erase-line`

Modes 0/1/2 per spec. Fill target cells with default cell (reset
attrs) at each position.

Commit: `feat(screen): 5e.3 — erase-display and erase-line`.

### 5. 5e.4b — apply parsed SGR to cursor attrs

Consume `5e.4a` output, mutate the cursor's default `cell` attrs
that future `:print` events inherit. Handle `:reset t` -> clear all.

Commit: `feat(screen): 5e.4b — apply SGR to cursor attrs`.

### 6. 5e.5 — apply `:bs :cr :lf :ht` (needs 5d + 5e.1)

Simple controls. `:bs` decrement col (clamp). `:cr` col := 0.
`:lf` advance row; at bottom -> push top to scrollback and scroll.
`:ht` advance to next tab stop (every 8 cols).

Commit: `feat(screen): 5e.5 — simple controls with scroll-on-lf`.

### 7. 5g — screen->html (needs 37928's 5f)

`(screen->html screen)` renders the grid, grouping consecutive cells
with identical attrs into one `<span style="color:#X;background:#Y;
font-weight:bold">TEXT</span>`. Test with a screen whose cells have
mixed attrs — assert that same-attr runs collapse into single spans.

Commit: `feat(screen): 5g — screen->html with attr span runs`.

## Rules

- 1 task = 1 commit. No scope creep.
- Push after each commit to origin track-b/ansi-parser.
- Never touch files owned by 37928: `src/screen.lisp` grid/cursor
  bits, `src/screen-scrollback.lisp`, and integration scenarios.
  You may add new files (`src/sgr.lisp`, `src/screen-html.lisp`) and
  extend the dispatcher via `(defmethod apply-event ...)` or the
  dispatch-table pattern 37928 picks.
- If you're blocked waiting on 37928, do not invent. Commit what
  you have, then `git pull` + re-check every few minutes.
- If you hit a 20-minute dead end, append the unknown to this file
  and stop.

## Completion signal

When 5h integration scenario (owned by 37928) passes, the track is
done. Report that and stop.
