# photo-ai-lisp

photo-ai-lisp is a Common Lisp construction photo manifest management app. It is a small public prototype aimed at managing photo-oriented manifest data with a simple Lisp-first stack rather than a conventional deploy-heavy web workflow.

The project is intentionally inspired by the live-editing development experience associated with Viaweb and Yahoo Store: write into a running server from the REPL, skip a separate deploy step during development, and generate HTML through S-expressions. The goal is to recreate that style of personal web application development on a private domain using modern Common Lisp tooling.

This repository is also a practical learning project for studying ideas from On Lisp through an actual application instead of isolated exercises. The initial stack is SBCL, Hunchentoot, and cl-who, kept deliberately small so the runtime editing loop stays easy to understand.

The code is released under the MIT License. Current status: WIP skeleton.
