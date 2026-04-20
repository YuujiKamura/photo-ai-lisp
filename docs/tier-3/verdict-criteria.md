# KEEP / ARCHIVE — Pre-Registered Quantitative Criteria (T3.d)

Pre-registered before dogfood week starts. No vibe-based judgment; the verdict
is computed mechanically from `usage.log` + checkpoint notes.

---

## 1. Definitions

### 1.1 `hub_commands` (weekly total)

Count of `INPUT` lines in `~/.photo-ai-lisp/usage.log` where:

- `verb` field == `INPUT` (exact string, case-sensitive)
- `bytes` field > `0` (zero-byte inputs excluded — protocol keepalives)
- Timestamp falls within the dogfood week (Mon 00:00:00 UTC through Sun
  23:59:59 UTC, inclusive)

Counting command (bash):

```bash
awk -F'\t' '$2=="INPUT" && $4+0 > 0' ~/.photo-ai-lisp/usage.log \
  | grep "^2026-W<week>" | wc -l
```

`BOOT` and `SHUTDOWN` lines are **never** counted (per T3.b §5).
`SHOW` / `STATE` / `LIST` lines are **never** counted; they are queries, not
commands issued by the user (per T3.b §5).

### 1.2 `cli_commands` (weekly total)

Self-reported count from daily checkpoint files (`docs/tier-3/checkpoints/`).
Defined as: terminal invocations of `photo-ai-go` stages typed outside the hub
during the same dogfood week.

Sum of the "CLI-driven" column across all five checkpoint files
(`mon.md` … `fri.md`).

### 1.3 `frustration_severity` values

All non-empty "Severity" cells from the "UX Frustrations" table in each of the
five daily checkpoint files. Exactly the integers 1–5 recorded there; empty
rows are excluded from the mean.

### 1.4 `hub_unavailable_day`

A calendar day (UTC) is counted as **hub-unavailable** if `usage.log` contains
no `INPUT` line with `bytes > 0` for that date AND the checkpoint note for that
day records a reason the hub could not be used (connection error, crash, etc.).
Days where the user simply chose not to run a case are **not** counted.

---

## 2. KEEP Conditions (all three must hold)

| # | Condition | Formula |
|---|-----------|---------|
| K1 | Hub-adoption ratio | `hub_commands / (hub_commands + cli_commands) >= 0.40` |
| K2 | Mean frustration severity | `mean(frustration_severity) <= 3.0` |
| K3 | Hub-unavailable days | count of `hub_unavailable_day` across the week `== 0` |

**KEEP** iff K1 AND K2 AND K3.

---

## 3. ARCHIVE Condition

**ARCHIVE** iff any one of K1, K2, K3 fails.

There is no partial result. Breaking a single condition triggers ARCHIVE.

---

## 4. Tie-Break / Boundary Cases

| Scenario | Resolution |
|----------|-----------|
| `hub_commands + cli_commands == 0` (no activity recorded) | Automatic **ARCHIVE** — no data means the hub was not used |
| `frustration_severity` list is empty (no frustrations recorded all week) | K2 vacuously satisfied (`mean` of empty set = `0.0 <= 3.0`); proceed to K1 and K3 |
| Exactly `hub_commands / total == 0.40` | K1 satisfied (condition is `>=`) |
| Exactly `mean(frustration_severity) == 3.0` | K2 satisfied (condition is `<=`) |
| A hub outage day is also a day with zero case runs (no photos to process) | Day does **not** count as `hub_unavailable_day` — no demand, no unavailability |

---

## 5. Sync with T3.b INPUT Semantics

The `hub_commands` counter maps 1-to-1 to the `INPUT` count defined in
`docs/tier-3/usage-log-format.md` §5 ("Total INPUTs during dogfood week").
Specifically:

- Same filter: `verb == INPUT` AND `bytes > 0`
- Same scope: the five dogfood weekdays
- Same exclusions: BOOT, SHUTDOWN, SHOW, STATE, LIST

The only difference is that `verdict-criteria.md` also requires the ratio
comparison against `cli_commands`; T3.b only specifies the absolute floor
(`>= 15 INPUTs/week`). Both conditions apply independently; T3.b's floor
(K0, implicitly) is subsumed by K1 in typical usage but is not redundant when
`cli_commands` is near zero.

---

## 6. Verdict File

The verdict is recorded in `docs/tier-3-verdict.md` (T3.f) after the week
ends. That file must begin with `KEEP` or `ARCHIVE` on its first line, followed
by computed values for K1, K2, K3 and links to each checkpoint file.
