#!/usr/bin/env bash
# Find sbcl in this order: $SBCL env -> PATH -> common install paths.
# Override by setting SBCL=/path/to/sbcl.exe before running.
# Once the hub is listening on :8090, open a Chrome --app window unless
# NO_APP_WINDOW=1 is set. Override Chrome path via CHROME=/path/to/chrome.exe.
set -u

find_sbcl() {
  if [[ -n "${SBCL:-}" ]]; then
    printf '%s' "$SBCL"
    return 0
  fi
  if command -v sbcl >/dev/null 2>&1; then
    printf '%s' sbcl
    return 0
  fi
  local candidates=(
    "/c/Program Files/Steel Bank Common Lisp/sbcl.exe"
    "${USERPROFILE:-$HOME}/SBCLLocal/PFiles/Steel Bank Common Lisp/sbcl.exe"
    "${LOCALAPPDATA:-$HOME}/Programs/Steel Bank Common Lisp/sbcl.exe"
    "/c/sbcl/sbcl.exe"
    "/opt/sbcl/bin/sbcl"
    "/usr/local/bin/sbcl"
  )
  local p
  for p in "${candidates[@]}"; do
    if [[ -x "$p" ]]; then
      printf '%s' "$p"
      return 0
    fi
  done
  return 1
}

find_chrome() {
  if [[ -n "${CHROME:-}" ]]; then
    printf '%s' "$CHROME"
    return 0
  fi
  local candidates=(
    "/c/Program Files/Google/Chrome/Application/chrome.exe"
    "/c/Program Files (x86)/Google/Chrome/Application/chrome.exe"
    "/c/Program Files (x86)/Microsoft/Edge/Application/msedge.exe"
    "/c/Program Files/Microsoft/Edge/Application/msedge.exe"
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
  )
  local p
  for p in "${candidates[@]}"; do
    if [[ -x "$p" ]]; then
      printf '%s' "$p"
      return 0
    fi
  done
  for cmd in google-chrome chromium chromium-browser; do
    if command -v "$cmd" >/dev/null 2>&1; then
      printf '%s' "$cmd"
      return 0
    fi
  done
  return 1
}

if ! sbcl_bin=$(find_sbcl); then
  cat >&2 <<'EOF'
ERROR: sbcl not found.

Install SBCL from https://www.sbcl.org/platform-table.html, then either:
  - add it to PATH, or
  - set the SBCL env var, e.g.:
      SBCL=/c/Users/you/sbcl/sbcl.exe bash scripts/demo.sh
EOF
  exit 1
fi

# Background: wait for :8090 to accept, then launch a Chrome --app window.
if [[ "${NO_APP_WINDOW:-}" != "1" ]]; then
  (
    if chrome_bin=$(find_chrome); then
      for _ in $(seq 1 40); do
        if (echo > /dev/tcp/localhost/8090) 2>/dev/null; then
          "$chrome_bin" --app=http://localhost:8090/ --window-size=1280,780 \
            >/dev/null 2>&1 &
          exit 0
        fi
        sleep 0.5
      done
    fi
  ) &
fi

exec "$sbcl_bin" --load "$(dirname "$0")/demo.lisp"
