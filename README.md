# photo-ai-lisp

photo-ai-lisp is a Common Lisp construction photo manifest management app. It is a small public prototype aimed at managing photo-oriented manifest data with a simple Lisp-first stack rather than a conventional deploy-heavy web workflow.

The project is intentionally inspired by the live-editing development experience associated with Viaweb and Yahoo Store: write into a running server from the REPL, skip a separate deploy step during development, and generate HTML through S-expressions. The goal is to recreate that style of personal web application development on a private domain using modern Common Lisp tooling.

This repository is also a practical learning project for studying ideas from On Lisp through an actual application instead of isolated exercises. The initial stack is SBCL, Hunchentoot, and cl-who, kept deliberately small so the runtime editing loop stays easy to understand.

## Local Development

Install SBCL and Quicklisp first. On Windows, `choco install sbcl` is the simplest native path; for a smoother Lisp workflow, WSL is also a reasonable option. On macOS, `brew install sbcl` works. Then download the Quicklisp installer: `curl -O https://beta.quicklisp.org/quicklisp.lisp`, start SBCL with `sbcl --load quicklisp.lisp`, then run `(quicklisp-quickstart:install)` and `(ql:add-to-init-file)`.

Make the project visible to Quicklisp by cloning or symlinking this repository into `~/quicklisp/local-projects/`. Then start SBCL and run `(ql:quickload :photo-ai-lisp)` followed by `(photo-ai-lisp:start)`. The app will be available at <http://localhost:8080>.

The intended development loop is Viaweb-style live editing: redefine functions from the REPL while the server is running, reload the browser, and immediately see the new behavior without a separate build or deploy step. SLIME, Sly, or Alive all fit this workflow well and make the edit-eval-refresh cycle much more comfortable.

## Persistence

Photos are saved to `~/.photo-ai-lisp/photos.store` via `cl-store` on every mutation. The store is loaded automatically on start. Delete that file to reset the local state.

The code is released under the MIT License. Current status: WIP skeleton.
