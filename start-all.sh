#!/bin/zsh
set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"

lsof -ti tcp:5000 | xargs kill -9 2>/dev/null || true
lsof -ti tcp:3000 | xargs kill -9 2>/dev/null || true
lsof -ti tcp:80 | xargs kill -9 2>/dev/null || true

URL="http://localhost:5000/visualize.html"

(
  for i in {1..40}; do
    if curl -fsS "$URL" >/dev/null 2>&1; then
      open "$URL"
      exit 0
    fi
    sleep 0.25
  done
  open "$URL"
) &

BACKEND_PID=""

if [ -d "$PROJECT_DIR/v4-cokapi" ]; then
  (
    cd "$PROJECT_DIR/v4-cokapi"
    export PORT=3000

    if [ -f "cokapi.js" ]; then
      node cokapi.js
    elif [ -f "server.js" ]; then
      node server.js
    elif [ -f "package.json" ]; then
      npm start
    else
      echo "Found v4-cokapi, but could not find cokapi.js, server.js, or package.json."
    fi
  ) &

  BACKEND_PID=$!
  echo "Started C/C++ backend attempt."
else
  echo "No v4-cokapi folder found, so only the frontend will start."
fi

cleanup() {
  if [ -n "$BACKEND_PID" ]; then
    kill "$BACKEND_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

echo "Starting cpp-tutor..."
echo "Browser will open automatically at:"
echo "$URL"

"$PROJECT_DIR/start-cpp-tutor.sh"
