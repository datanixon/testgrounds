#!/usr/bin/env bash
# Smoke test: syntax-check game.js, then boot the game headless and play one
# full turn (player summons + end turn, AI plays its whole turn).
# Pass = "SMOKE PASS" printed, exit 0. All overnight sessions must run this
# before committing.
set -u

cd "$(dirname "$0")"

echo "[1/2] node --check game.js"
node --check game.js || { echo "SMOKE FAIL: syntax error"; exit 1; }

CHROME="C:/Program Files/Google/Chrome/Application/chrome.exe"
OUT="$(mktemp)"
trap 'rm -f "$OUT"' EXIT

echo "[2/2] headless one-turn play-through"
"$CHROME" --headless=new --disable-gpu --mute-audio \
  --window-size=1600,1100 --force-device-scale-factor=1 \
  --virtual-time-budget=30000 --dump-dom \
  "file:///$(pwd -W 2>/dev/null || pwd)/index.html#smoke" > "$OUT" 2>/dev/null

MARKER="$(grep -o 'SMOKE_[A-Z_]*[^<]*' "$OUT" | head -1)"
if [[ "$MARKER" == SMOKE_OK* ]]; then
  echo "SMOKE PASS: $MARKER"
  exit 0
else
  echo "SMOKE FAIL: ${MARKER:-no marker found (boot crash?)}"
  exit 1
fi
