#!/bin/zsh
set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"

if ! docker image inspect cpp-tutor/opt-cpp-backend-cpp20-sb:local >/dev/null 2>&1; then
  echo "Missing cpp-tutor/opt-cpp-backend-cpp20-sb:local image."
  echo "Build the stable local backend first with ./build-cpp20-backend.sh."
  exit 1
fi

docker build \
  --platform linux/amd64 \
  -t cpp-tutor/opt-cpp-backend-valgrind327:experimental \
  -f "$PROJECT_DIR/local-cpp20-backend/Dockerfile.valgrind327" \
  "$PROJECT_DIR/local-cpp20-backend"

docker build \
  --platform linux/amd64 \
  -t cpp-tutor/opt-cpp-backend-valgrind327-sb:experimental \
  -f "$PROJECT_DIR/local-cpp20-backend/Dockerfile.valgrind327.preserve-display" \
  "$PROJECT_DIR/local-cpp20-backend"
