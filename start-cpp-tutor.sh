#!/bin/zsh
set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
VENV_PY="$PROJECT_DIR/.venv/bin/python"

if [ ! -x "$VENV_PY" ]; then
  echo "Creating Python virtual environment..."
  python3 -m venv "$PROJECT_DIR/.venv"
  "$VENV_PY" -m pip install --upgrade pip
  "$VENV_PY" -m pip install bottle
fi

if [ -d "$PROJECT_DIR/v5-unity" ]; then
  V5_DIR="$PROJECT_DIR/v5-unity"
elif [ -d "$PROJECT_DIR/OnlinePythonTutor/v5-unity" ]; then
  V5_DIR="$PROJECT_DIR/OnlinePythonTutor/v5-unity"
else
  echo "Could not find v5-unity inside:"
  echo "$PROJECT_DIR"
  exit 1
fi

cd "$V5_DIR"

echo "Starting cpp-tutor frontend..."
echo "Open this in your browser:"
echo "http://localhost:5000/visualize.html"
echo

"$VENV_PY" bottle_server.py
