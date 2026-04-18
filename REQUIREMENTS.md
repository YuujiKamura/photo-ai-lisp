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

- **Lisp server** — byte pipe + session state + business API. Does *not*
  parse VT / ANSI. Does *not* render terminal output.
- **Browser frontend** — business UI + terminal widget. Terminal emulation
  is handled entirely by ghostty-web (vendored WASM + ES module).
- **Agent subprocess** — real child process (`cmd.exe` / `bash` / `claude -p`
  etc.), full shell access, stdout/stdin piped through the WebSocket.

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
