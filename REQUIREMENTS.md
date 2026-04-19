# photo-ai-lisp Requirements (SSOT)

This file is the single source of truth for what photo-ai-lisp is for and
what it is not. Every code change, new route, new agent task, and new
commit must map back to a numbered item here. If it doesn't map, stop.

Read this before `LESSONS.md`, before `HANDOVER.md`, before any issue or
plan. Those are evidence and context; this is the goal.

Anything below this line is a direct quote or paraphrase of the human
operator. If an AI wants to add something, open an issue and get explicit
sign-off first — do **not** edit this file with aspirational items.

---

## 1. Core vision

Single-screen application where:

- a **full-access terminal** (a real shell with `claude` / `gemini` /
  `codex` running inside it — "the brain") occupies one pane;
- **business UI** (case editor, photo browser, master viewer, pipeline
  status) occupies the rest of the same screen;
- **both panes live in the same browser page and the same server session**,
  so they share scope automatically.

Value prop in one sentence: **the agent in the terminal already knows
which case, which paths, and which data groups the user is editing,
without the user having to re-specify it.**

If that zero-re-specification property is not achievable for a proposed
feature, the feature is off-scope.

## 2. Boundary

The Lisp layer confines itself to **orchestration + DSL**. Everything else
is a subprocess or a vendored frontend. The boundary is now split into two
sub-sections (decision: issue #16).

### §2a — Lisp owns (author and evolve in Lisp)

1. **Pipeline DSL** — s-expression composition of skill invocations:
   `(pipeline (scan :dir d) (infer-scope) (match :priority '(工種 種別))
   (resolve-pairs) (export-xlsx))`. Macros let steps be swapped at the
   REPL without restart.
2. **Rule engine** — matching rules as data, e.g.
   `(rule :when (and (mono :アスファルト) (role :敷均し)) :pass-to :温度サイクル後処理)`.
   Historic Lisp territory.
3. **`case` CLOS model + session state** — `defclass case`, `defmethod
   run-skill ((s skill) (c case)) ...`, one `*session*` broker that UI
   and agent subprocess share.
4. **WebSocket / HTTP acceptor + subprocess supervisor** — byte pipe and
   skill dispatch for ghostty-web and Claude/Gemini subprocesses.
5. **REPL as live development surface** — redefine a rule and re-run a
   step without tearing down the server. The reason to pick Lisp for the
   orchestration layer at all.

Expected code volume: 3000–5000 lines of Lisp (~20–30% of total product,
~100% of domain-specific IP).

### §2b — Lisp wraps (thin shim only, real implementation elsewhere)

| Domain | Why Lisp loses here | External tool |
|---|---|---|
| XLSX write + image embed | cl-xlsx write-side is a rels-integrity pit; wrong rIds silently corrupt files | Python (openpyxl) or Go (excelize) subprocess |
| Image ops (thumb, EXIF, OCR) | No Pillow / Tesseract equivalent in CL | Python subprocess |
| Claude / Gemini API | No official SDK; hand-rolled HTTP = eternal rot | CLI subprocess + OAuth (see `feedback_no_api_key_default`) |
| YOLO / Gemma inference | Numerical ecosystem too thin in CL | Python + ONNX Runtime, or Rust via photo-ai-rust |
| Browser UI / VT emulation | Browser is not a Lisp target; ghostty-web already solves VT | ES module, plain JS glue |
| Windows pipe / CRLF decoding | flexi-streams + hunchensocket text-frame bugs already cost days | Binary frames, minimal surface |

**Non-negotiable rule**: if a mature library exists in Python/Go/Rust with
a decade of active maintenance, wrap it via pipe — do NOT reimplement it
in Lisp. `LESSONS.md` 2026-04-18 drift (VT engine rewrite) is the
cautionary tale.

**XLSX read-side exception**: reading cell values via `zip` + XML parsing
is within §2a scope. Only the write-side (image embed, styles.xml, chart,
rels coordination) delegates to subprocess.

### `src/*.lisp` ownership map

| File | §2 side | Rationale |
|---|---|---|
| `package.lisp` | §2a | Package definitions — pure DSL infrastructure |
| `main.lisp` | §2a | HTTP acceptor, startup, subprocess supervisor |
| `case.lisp` | §2a | `defclass case`, session broker, CLOS domain model |
| `pipeline.lisp` | §2a | Pipeline DSL — s-expression skill composition |
| `agent.lisp` | §2a | Agent subprocess lifecycle management |
| `business-ui.lisp` | §2a | Business API WebSocket/REST handlers |
| `proc.lisp` | §2a | Subprocess spawning — the supervisor side of §2a item 4 |
| `term.lisp` | §2b | Byte-pipe shim for ghostty-web WASM; wraps an external VT system, not authored in Lisp |

## 3. Scope sharing (the core mechanism)

The browser session has one `*session*` object owned by the Lisp server.
UI state changes write into it; agent subprocess reads from it.

Propagation:

- **UI → session**: WebSocket / REST writes (`/api/session/*`).
- **session → agent**: env vars on spawn, initial stdin lines, MCP server
  exposing a `get-scope` tool, or (last resort) restart the agent with
  fresh context.

Fields in scope (minimum viable set, extend only as requirements grow):

- current case / project identifier
- case root path on disk
- current selection (files, photo groups)
- active reference masters
- last pipeline result pointer

## 4. Anti-scope (do not build)

These have been explicitly ruled out. Adding any of them without
updating this section first is a requirements violation.

- **A second terminal emulator**. ghostty-web is final for the VT layer.
  The archived `track-b/ansi-parser` Lisp VT engine is not coming back.
- **Marketing / landing pages / multi-framing README pivots.** See
  `LESSONS.md` §"2026-04-18 drift".
- **Stand-alone "run a shell in the browser" features** beyond what's
  needed to demonstrate scope sharing.
- **Parallel terminal stacks** (xterm.js fallback, Tauri shell, native
  winpty wrapper, etc.).
- **Routes, pages, or handlers that exist only because they might be
  useful.** Every handler must tie to a field in §3 or a flow under §5.
- **Lisp-native XLSX authoring** (image embed, styles.xml, chart, rels
  coordination). Write-side is exclusively subprocess (openpyxl/excelize).
  Past drift evidence: issue #16, `LESSONS.md` 2026-04-18.
- **Lisp-native image processing** (thumbnailing, EXIF extraction, OCR).
  Delegate to Python subprocess.
- **Lisp-native Claude or Gemini HTTP client**. Use CLI subprocess + OAuth.
  Hand-rolled HTTP against evolving AI APIs is eternal rot. See `feedback_no_api_key_default`.

## 5. Concrete flows (to be filled in as they become requirements)

- 5.1 *placeholder* — Open a case → agent pane auto-`cd`s to case root
  and has the reference master path in env. Not yet implemented.
- 5.2 *placeholder* — Select photos in UI → agent can ask "what is the
  current selection" and receive the list. Not yet implemented.
- 5.3 *placeholder* — Run a skill (e.g. `photo-scan`) from the UI →
  output streams to the terminal pane → resulting JSON appears in the
  UI result panel. Not yet implemented.

(Add a new numbered flow only when the human asks for it. Do not
invent 5.4 because "it would be nice".)

## 6. Working rules

Applies to every contributor, human or AI.

- Every new function has a test. "Tests later" is a violation.
- Every new feature is demonstrated by a running screen (screenshot or
  live smoke), not by a status report.
- No intermediate progress narration. Deliver, then report once.
- External actions (PR, issue, upstream push, public repo exposure)
  require explicit per-action approval from the human operator.
- If a task requires something not covered by §1-§5, **stop and ask**.

## 7. Open questions (not requirements yet)

- Business entity model beyond "case": job, site, date range, photo
  group — what are the first-class nouns?
- Scope change semantics: does switching cases restart the agent, or
  live-update it?
- Multi-agent panels: one subprocess per case (isolated), or one global
  agent that re-scopes?
- Persistence: does session survive server restart?

These become §5 flows (and sometimes §3 fields) once the human resolves
them. Until then they are not work to do.
