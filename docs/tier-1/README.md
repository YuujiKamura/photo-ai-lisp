# Tier 1 — Wire up evidence (issue #19)

Tier 1 of Track T proves the wire works end-to-end: a Common-Lisp `cp-client` can open a WebSocket to a running `deckpilot` daemon and drive a real child session through the four CP verbs. After Atom 17.4 ("Purge") removed all PTY ownership from the Lisp side, Tier 1 is the smallest honest demonstration that Lisp is now a pure CP client and that `deckpilot` owns every terminal. The three logs below close out the atoms T1.a, T1.b, and T1.c; the verdict machinery in Tier 2 and Tier 3 is layered directly on top of this foundation.

- [`ws-handshake.log`](ws-handshake.log) — T1.a: first `ws://127.0.0.1:8080/ws` handshake; LIST returned 29 sessions and STATE on a stale id correctly returned `session not found`.
- [`cp-roundtrip.log`](cp-roundtrip.log) — T1.b: four-verb round-trip (LIST / STATE / INPUT / SHOW) against live session `ghostty-30028` via `scripts/cp-smoke.lisp`; all returned `:ok t` and SHOW's base64 decoded to the real `echo t1b-ping` output.
- [`boot-hub.log`](boot-hub.log) — T1.c: `sbcl --script scripts/boot-hub.lisp` exited 0 with empty stderr, printed `[BOOT] ok`, and LIST reported session-count=33, validating the one-shot entry point for Tier 2.

See `BACKLOG.md` Track T Tier 1 for the atom-level DoD checkboxes.
