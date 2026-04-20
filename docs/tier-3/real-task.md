# Tier 3 Real Task — T3.a decision

**Task**: drive the photo-import pipeline (工事写真 matching) through
the Lisp hub instead of invoking `photo-ai-go` directly in a terminal.

## Why this task

- **Already daily usage** — user runs this pipeline multiple times per
  working day on live photos; counts come from real work, not a
  rehearsal that would false-signal KEEP.
- **Single-agent scope** — fits the Tier 2 fixed
  `claude --model sonnet` session; no multi-session scheduling leaks
  into the verdict window (Issue #19 defers multi-agent post-verdict).
- **Eyeball-able artifacts** — each run yields `matched.json`, Excel,
  and PDF, so frustration becomes concrete ("wrong row matched", "PDF
  cropped") rather than vibes.

## Inputs

- Case directory (photos + black-board EXIF; one 工事案件 per run).
- Master CSV (マスタ: 工種 × 種別 × 細別 for the case).
- Reference JSON (optional; regression-check vs an existing 正解写真帳).

## Outputs

- `matched.json` — one entry per photo with resolved master row and
  tiebreaker notes.
- Excel listing — openpyxl, one row per photo, master columns joined.
- Photo-book PDF — reportlab A4, 3-up, caption from the matched row.

## Daily usage this replaces

Per case today the user runs `photo-ai-go` stages (scan →
keyword-extract → match → export) from a terminal. 3–5 case runs per
working day, ≈ 12–20 stage invocations, all typed outside any Lisp hub.

## How the Lisp hub drives it

1. Browser opens `/cases/:id` in `business-ui`.
2. A form button POSTs the case path; `pipeline-cp` formats the stage
   command and sends it as a CP `INPUT` frame to `*demo-session-id*`
   (the fixed `claude --model sonnet` session on deckpilot `/ws`).
3. Claude invokes the `photo-ai-go` stage as a shell child of its PTY;
   stdout streams back via ghostty-web.
4. The ghostty-web iframe shows live output; `matched.json` / Excel /
   PDF land in the case directory as today.

No Lisp PTY ownership, no Phase 5 screen buffer, no Phase 7 tool
intercept — the hub only does INPUT dispatch + SHOW echo.

## Dogfood week measurement

- Every CP verb sent by `pipeline-cp` appends one line to
  `~/.photo-ai-lisp/usage.log` in the T3.b format
  (`<iso8601>\t<verb>\t<session>\t<payload-bytes>`).
- Week-end tally: **KEEP** iff ≥ 15 `INPUT` rows across the five
  weekdays **AND** checkpoint notes report less terminal switching.
  **ARCHIVE** otherwise.
- 15 = ~3 case runs × ~4 stages × 1 weekday of real adoption; lower
  means the hub failed to insert itself into the existing habit loop.
