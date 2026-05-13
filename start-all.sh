#!/usr/bin/env bash
set -euo pipefail

ROOT="$HOME/pathrise-python-tutor"
V4="$ROOT/v4-cokapi"
V5="$ROOT/v5-unity"

cd "$ROOT"

docker info >/dev/null 2>&1 || open -a Docker

pkill -f 'bottle_server.py' 2>/dev/null || true
pkill -f 'cokapi.js http3000' 2>/dev/null || true

cleanup() {
  if [[ -n "${BOTTLE_PID:-}" ]]; then
    kill "$BOTTLE_PID" 2>/dev/null || true
  fi
  if [[ -n "${COKAPI_PID:-}" ]]; then
    kill "$COKAPI_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

echo "Starting C/C++ backend on http://localhost:3000 ..."
cd "$V4"
node cokapi.js http3000 &
COKAPI_PID=$!

sleep 2

echo "Starting Bottle server on http://localhost:5000 ..."
cd "$V5"
source .venv/bin/activate
python bottle_server.py &
BOTTLE_PID=$!

sleep 2

echo
echo "Open: http://localhost:5000/visualize.html"
echo "Press Ctrl+C here to stop both servers."

wait "$BOTTLE_PID"
