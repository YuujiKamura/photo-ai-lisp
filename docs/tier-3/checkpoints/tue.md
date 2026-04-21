# Daily Checkpoint — 2026-04-21 (Tue, Day 1/4)

**Date**: `2026-04-21`

Tier 3 dogfood week kick-off. Schedule: Tue–Fri (4 days); per-day
threshold derived by pro-rating the weekly KEEP bar (`≥15 hub INPUTs /
week → ≈4/day`).

---

## 1. Command Counts

| Channel | Count | Notes |
|---------|-------|-------|
| Hub-driven (`INPUT` lines in `usage.log` with `bytes > 0`) | `0` | C1 landed (initial `4e3cc05`, amended to record SHA); script greps `\tINPUT\t` lines with `bytes > 0` from `~/.photo-ai-lisp/usage.log` |
| CLI-driven (terminal invocations, self-reported) | `_______` | photo-import CLI runs outside the hub |

> **Hub ratio for today**: `hub_commands / (hub_commands + cli_commands)` = `_______`

---

## 2. Blockers / ハマり

- **Bug 1 — iframe src double-path** (`*ghostty-web-url*` default `/shell`
  × template `"~a/shell?case=~a"` → `/shell/shell?case=...` 404). Hit
  during T2.g capture 2026-04-21. Fixed today in `src/business-ui.lisp`
  @ `cf26bc4` (template now `"~a?case=~a"`, `*ghostty-web-url*` is now
  the full iframe base URL per updated docstring) so dogfood is measuring
  hub UX, not workaround-applied UX.
  Caveat: new `business-ui-suite` tests not yet wired into
  `photo-ai-lisp-tests` `run-tests` entry — CI green confirms *no
  regression* but didn't actually exercise the 2 new asserts. Separate
  follow-up needed to wire the suite.
- **Bug 2 — orphan port 8090 LISTENING** after previous session SBCL
  crash (PID 7344 dead, socket held). Workaround: start hub on :8091
  via `photo-ai-lisp:start :port 8091`. Root cause (graceful shutdown
  on SIGINT) deferred; low priority if re-occurrence stays rare.
- **Bug 3 — `.gitignore` excludes `demo.log`** — forced with `git add -f`
  during T2.g commit. Cosmetic; `!docs/**/demo.log` whitelist to be
  added when convenient.

### Deferred to #30 G5.b (post-Fri)

Scope items identified by the C1 review that do not affect the Fri
2026-04-24 verdict (verdict only counts `INPUT` lines and the demo
path is Mode 1 shell-broadcast):

- Mode 2 legacy CP path does not write `INPUT` log lines (demo path
  is Mode 1, so the verdict is unaffected this week).
- `BOOT` / `SHUTDOWN` verbs not emitted despite being in the closed
  verb set (see `+usage-log-verbs+` in `src/usage-log.lisp`).
- ISO 8601 ms field not synchronized with the UTC second boundary
  (derived from `get-internal-real-time` modulo 1000; process-local
  epoch). `refs #30`.

---

## 3. UX Frustrations

| Description | Severity (1–5) |
|-------------|----------------|
| `_______` | `_______` |

---

## 4. Time-to-Task

Time from first hub command to final output artifact:

| Case / Run | First INPUT (ISO 8601) | Output ready | Elapsed |
|------------|------------------------|--------------|---------|
| `_______` | `_______` | `_______` | `_______` |

---

## 5. その日の所感

Tier 2 demo が mock ticked から real shell-broadcast round-trip
(T2.h pivot) に移行した日。Tier 3 開始は Bug 1 ランド後。usage-log
の自動書き出し (C1 sub) が未完なので、今日の hub INPUT 数は手動
tally。明日 (水) までに usage.log 自動化を潰したい。
