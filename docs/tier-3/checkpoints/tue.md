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

---

## 6. Phase 2 Landing Summary (PM4 handoff)

### Commits to main (today)

| SHA | Description |
|-----|-------------|
| `a8c484d` | merge: G1.a envelope 5-part (fiveam 160 / 154 run / 6 skip / 0 fail) |
| `5eb38df` | docs(g12a): ACP gap analysis (1782 words) |
| `bd14b6e` | merge: G1.b pending-request table (Code Reviewer 10/10 PASS) |
| `60a9a98` | merge: G2 status broadcast + UI spinner (Code Reviewer 13/13 PASS) |

Tip: main @ `60a9a98` is the reference SHA for the rest of the week.

### Fiveam delta

- Before PM4: **143** checks
- After PM4:  **234** checks (**+91**)
- Breakdown: Pass **228** / Skip **6** / **Fail 0**

### Phase 2 landing status

| Lane | Scope | Status |
|------|-------|--------|
| α    | G1.b pending-request table            | ✅ landed (`bd14b6e`) |
| β    | G2 status broadcast + UI spinner      | ✅ landed (`60a9a98`) |
| γ    | G12.a ACP gap analysis (docs)         | ✅ landed (`5eb38df`) |
| δ    | G1.c negotiation                      | ⛔ BLOCKED on deckpilot issue |
| ε    | G13.a MCP server (photo-ai-go)        | ↗️ separate repo / session |

### Tier 3 dogfood INPUT run today

**Actual hub INPUT runs: 0 件**. C1 usage-log landing (scaffolding above)
gives the measurement plumbing, but no real hub INPUT traffic was generated
on Day 1. Wed–Fri must hit **≥4/day × 3 days = ≥12** to reach the weekly
**≥16** bar (weekly target was re-scoped to ≥15; we aim ≥16 for headroom).

### Blockers / risks going into Day 2

- Day 1 zero-INPUT means the weekly budget is back-loaded onto Wed/Thu/Fri.
  Single slip day endangers the Fri verdict.
- δ (G1.c negotiation) stays parked until the deckpilot issue is decided;
  don't let it absorb Wed bandwidth — focus on INPUT generation first.
