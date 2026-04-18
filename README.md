# photo-ai-lisp

photo-ai-lisp is a Common Lisp construction photo manifest management app. It is a small public prototype aimed at managing photo-oriented manifest data with a simple Lisp-first stack rather than a conventional deploy-heavy web workflow.

The project is intentionally inspired by the live-editing development experience associated with Viaweb and Yahoo Store: write into a running server from the REPL, skip a separate deploy step during development, and generate HTML through S-expressions. The goal is to recreate that style of personal web application development on a private domain using modern Common Lisp tooling.

This repository is also a practical learning project for studying ideas from On Lisp through an actual application instead of isolated exercises. The initial stack is SBCL, Hunchentoot, and cl-who, kept deliberately small so the runtime editing loop stays easy to understand.

The code is released under the MIT License. Current status: WIP skeleton.

## Components

### ANSI Parser (`src/ansi.lisp`)

A state-machine based parser for ANSI / ECMA-48 escape sequences. It translates a stream of bytes into high-level events.

**Interface:**
- `(make-parser)`: Create a new parser state.
- `(parser-feed parser byte)`: Feed one byte, returns a list of events.
- `(parser-feed-string parser string)`: Feed a string, returns a list of events.

**Supported Events:**
- `(:type :print :char #\c)`: Printable character.
- `(:type :cursor-move :direction DIR :count N)`: Move cursor (DIR: `:up`, `:down`, `:right`, `:left`).
- `(:type :cursor-position :row R :col C)`: Set absolute cursor position.
- `(:type :erase-display :mode M)`: Erase screen parts (M: 0=down, 1=up, 2=all).
- `(:type :erase-line :mode M)`: Erase line parts (M: 0=right, 1=left, 2=all).
- `(:type :set-attr :attrs LIST)`: Set SGR attributes (colors, bold, etc.).
- `(:type :set-title :title STR)`: OSC title update.
- `(:type :bell)`, `(:type :bs)`, `(:type :ht)`, `(:type :lf)`, `(:type :cr)`: Control characters.
- `(:type :unknown :raw BYTES)`: Unhandled or malformed sequences.
