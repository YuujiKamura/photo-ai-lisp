#!/usr/bin/env bash
# Use sbcl from PATH. Override via SBCL env var if needed.
exec "${SBCL:-sbcl}" --load "$(dirname "$0")/demo.lisp"
