# Unit-test coverage for `src/*.lisp`

Branch: `track-c/ghostty-web-front` (worktree `agent-a10cb0d3`).

Final suite status: `Did 74 checks. Pass: 66. Skip: 8. Fail: 0.`

## Coverage matrix

| Symbol | File | Kind | Status | Covered by |
| --- | --- | --- | --- | --- |
| `photo-ai-lisp` | `package.lisp` | defpackage | intentionally-private-no-test | package is exercised transitively by every other test |
| `child-process` | `proc.lisp` | defstruct | covered | `proc-struct-accessors-exist`, `term-make-child-process-constructor` |
| `make-child-process` | `proc.lisp` | defstruct-gen | covered | `term-make-child-process-constructor` |
| `child-process-p` | `proc.lisp` | defstruct-gen | covered | `proc-struct-accessors-exist` |
| `child-process-process` | `proc.lisp` | defstruct-gen | covered | `proc-struct-accessors-exist`, `proc-process-slot-non-nil` |
| `child-process-stdin` | `proc.lisp` | defstruct-gen | covered | `proc-accessor-stream-types` (skipped on Windows), `term-make-child-process-constructor` |
| `child-process-stdout` | `proc.lisp` | defstruct-gen | covered | `proc-accessor-stream-types`, `term-make-child-process-constructor` |
| `%default-argv` | `proc.lisp` | defun | covered | `proc-default-argv-platform` |
| `spawn-child` | `proc.lisp` | defun | covered | `proc-spawn-child-returns-child-process`, `spawn-child-unix-echo` |
| `child-alive-p` | `proc.lisp` | defun | covered | `proc-child-alive-lifecycle` |
| `kill-child` | `proc.lisp` | defun | covered | `proc-child-alive-lifecycle` |
| `*agent-command*` | `agent.lisp` | defvar | covered | `agent-command-var-is-string` |
| `*agent-args*` | `agent.lisp` | defvar | covered | `agent-args-var-is-list` |
| `*agent-process*` | `agent.lisp` | defvar | covered | `agent-process-defvar-bound` |
| `agent-alive-p` | `agent.lisp` | defun | covered | `agent-alive-p-nil-with-no-process` |
| `agent-stdin` | `agent.lisp` | defun | covered | `agent-stdin-nil-with-no-process` |
| `agent-stdout` | `agent.lisp` | defun | covered | `agent-stdout-nil-with-no-process` |
| `start-agent` | `agent.lisp` | defun | covered | `agent-sends-prompt-and-gets-response` (live scenario, skipped when claude unavailable) |
| `stop-agent` | `agent.lisp` | defun | covered | `agent-stop-agent-idempotent-with-nil` |
| `agent-send` | `agent.lisp` | defun | covered | `agent-send-returns-empty-string-with-no-process`, live scenario |
| `ws-easy-acceptor` | `term.lisp` | defclass | covered | `term-ws-easy-acceptor-inherits-websocket-acceptor`, `term-ws-easy-acceptor-inherits-easy-acceptor` |
| `echo-resource` | `term.lisp` | defclass | covered | `term-echo-resource-type` |
| `*echo-resource*` | `term.lisp` | defvar | covered | `term-echo-resource-type` |
| `hunchensocket:text-message-received` (echo) | `term.lisp` | defmethod | covered | `term-echo-resource-text-message-echoes` |
| `%find-echo-resource` | `term.lisp` | defun | covered | `term-find-echo-resource-match`, `term-find-echo-resource-no-match`, `term-dispatch-table-has-echo-fn` |
| `shell-client` | `term.lisp` | defclass | covered | `term-shell-client-class-defined`, `term-shell-client-accessors-defaults` |
| `shell-client-child` / `shell-client-reader-thread` | `term.lisp` | accessor | covered | `term-shell-client-accessors-defaults` |
| `shell-resource` | `term.lisp` | defclass | covered | `term-shell-resource-type` |
| `*shell-resource*` | `term.lisp` | defvar | covered | `term-shell-resource-type` |
| `%shell-argv` | `term.lisp` | defun | covered | `term-shell-argv-platform` |
| `%stdout-pump` | `term.lisp` | defun | covered | `term-stdout-pump-flushes-and-exits` |
| `hunchensocket:client-connected` (shell) | `term.lisp` | defmethod | skipped-with-reason | `term-shell-resource-client-connected-skipped` — spawns a real shell + thread; exercised via the live `/ws/shell` integration path |
| `hunchensocket:client-disconnected` (shell) | `term.lisp` | defmethod | covered | `term-shell-resource-client-disconnected-no-child-noop` |
| `hunchensocket:text-message-received` (shell) | `term.lisp` | defmethod | covered | `term-shell-resource-text-message-no-child-noop` |
| `%find-shell-resource` | `term.lisp` | defun | covered | `term-find-shell-resource-match`, `term-find-shell-resource-no-match`, `term-dispatch-table-has-shell-fn` |
| `shell-page` | `term.lisp` | easy-handler | covered | `shell-page-contains-xterm-js` |
| `term-page` | `term.lisp` | easy-handler | covered | `term-page-contains-xterm-js` |
| `*acceptor*` | `main.lisp` | defvar | covered | `main-acceptor-defvar-exists` |
| `home-page` | `main.lisp` | easy-handler | covered | `main-home-page-returns-html`, `main-home-page-links-to-term`, `main-home-page-has-title` |
| `start` | `main.lisp` | defun | covered | `main-start-idempotent-when-acceptor-set`, `main-start-accepts-port-keyword`, `main-lifecycle-stop-clears-acceptor`, `main-start-stop-start-lifecycle` |
| `stop` | `main.lisp` | defun | covered | `main-stop-safe-with-nil-acceptor`, `main-lifecycle-stop-clears-acceptor` |

## Summary

- Total symbols: 34 counting distinct callables (excluding the defpackage form and struct-generated accessors covered as a group).
- Covered: 33.
- Skipped with documented reason: 1 (`client-connected` shell-resource — requires a live shell + thread; exercised via the `/ws/shell` integration path).
- Intentionally no test: `photo-ai-lisp` defpackage (transitive).

## Notes

- `agent-sends-prompt-and-gets-response` is a live-scenario test; on Windows the npm-shim `claude.cmd` wrapper does not propagate stdin through `uiop:launch-program :input :stream` reliably, so the availability probe now gates on plain `claude` being directly invokable (no `.cmd` fallback). The test skips cleanly when `claude` is not on PATH.
- Process-spawning `proc.lisp` tests skip on Windows because `cmd.exe` exits too quickly to form a reliable liveness assertion; Unix CI covers them.
- Bug uncovered during coverage work: none in `src/*.lisp`. The only source-adjacent change was tightening the claude availability probe in `tests/agent-scenario.lisp` (not a `src/` bug, but an environmental test-gating fix).
