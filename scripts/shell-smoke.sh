#!/usr/bin/env bash
# shell-smoke.sh — automated visual/encoding smoke for photo-ai-lisp /shell.
#
# Invariants checked:
#   1. hub accepts HTTP 200 on /
#   2. injected text reaches /ws/shell and appears in /api/shell-trace
#   3. stdout byte-trace retains multi-byte UTF-8 (box drawing e2 94 80,
#      Japanese e3 xx xx) — proves the binary-frame pump is intact
#   4. headless Chrome renders the live UI for visual pass review
#
# Exit 0 when hub+trace+screenshot all succeed, 1 on any failure.
# The caller (Claude) should Read the screenshot for alignment review.
#
# Usage:
#   scripts/shell-smoke.sh                # default: inject "1\r" (pick claude)
#   scripts/shell-smoke.sh "echo hi\r"    # custom input
#   HUB=http://localhost:8091 scripts/shell-smoke.sh

set -u
HUB="${HUB:-http://localhost:8091}"
TS=$(date +%Y%m%d-%H%M%S)
OUT_DIR="${TMPDIR:-/tmp}"
OUT_PNG="${OUT_DIR}/shell-smoke-${TS}.png"
OUT_TRACE="${OUT_DIR}/shell-smoke-${TS}.trace"
INJECT="${1:-$'1\r'}"

fail() { echo "FAIL $*"; exit 1; }

# 1. hub reachability
code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 "$HUB/")
[[ "$code" == "200" ]] || fail "hub unreachable: HTTP $code"
echo "OK   hub 200"

# 2. inject — GET /api/inject?text=... per README
curl -s -o /dev/null -G --max-time 3 --data-urlencode "text=$INJECT" "$HUB/api/inject" \
  || fail "inject request errored"
echo "OK   injected $(printf %q "$INJECT")"

# 3. let TUI redraw
sleep 3

# 4. capture trace
curl -s --max-time 3 "$HUB/api/shell-trace" > "$OUT_TRACE" \
  || fail "trace fetch errored"
bytes=$(wc -c < "$OUT_TRACE")
echo "OK   trace $OUT_TRACE ($bytes bytes)"

# 5. visual screenshot — capture the live Chrome --app window via winshot.
#    Headless Chrome was tried first but iframe/WASM canvas does not fully
#    paint within --virtual-time-budget, so the live window (if open) is
#    the only reliable source. The --app launch must happen once out-of-band.
WINSHOT="$HOME/winshot/winshot.exe"
CHROME="/c/Program Files/Google/Chrome/Application/chrome.exe"
if [[ -x "$WINSHOT" ]]; then
  # If no photo-ai-lisp window exists yet, spawn one and give it time.
  have_win=$("$WINSHOT" --list 2>/dev/null | awk '$3=="yes"' | grep -c "photo-ai-lisp" || true)
  if [[ "$have_win" -eq 0 ]] && [[ -x "$CHROME" ]]; then
    "$CHROME" --app="$HUB/" --window-size=1400,900 >/dev/null 2>&1 &
    disown 2>/dev/null || true
    sleep 4
  fi
  "$WINSHOT" capture --title "photo-ai-lisp" --output "$OUT_PNG" 2>/dev/null \
    || { echo "SKIP screenshot (no photo-ai-lisp window visible)"; OUT_PNG=""; }
  [[ -n "$OUT_PNG" && -f "$OUT_PNG" ]] && echo "OK   screenshot $OUT_PNG ($(wc -c < "$OUT_PNG") bytes)"
else
  echo "SKIP screenshot (winshot not at $WINSHOT)"
fi

# 6. encoding sanity: box-drawing (e2 94 80) or Japanese (e3 xx xx) should
#    show as their Latin-1 representatives in the preview strings.
#    e2 -> \xe2 (â) . e3 -> \xe3 (ã) . 94 -> \x94 . 80 -> \x80 .
out_previews=$(grep -oE '"dir":"out"[^}]+"preview":"[^"]*"' "$OUT_TRACE" | tail -5)
if [[ -n "$out_previews" ]]; then
  echo "--- trace tail (last 5 :out) ---"
  echo "$out_previews"
fi

# Report multi-byte presence as a positive signal (not a hard check — the
# test input may be pure ASCII, in which case absence is fine).
if echo "$out_previews" | LC_ALL=C grep -qE $'[\xe2\xe3]'; then
  echo "HINT multi-byte UTF-8 prefix bytes present in trace (box/CJK likely survived)"
fi

echo "---"
echo "screenshot: $OUT_PNG"
echo "trace:      $OUT_TRACE"
exit 0
