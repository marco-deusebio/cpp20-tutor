#!/bin/zsh
set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"

docker build \
  --platform linux/amd64 \
  -t cpp-tutor/opt-cpp-backend-cpp20:local \
  -f "$PROJECT_DIR/local-cpp20-backend/Dockerfile" \
  "$PROJECT_DIR/local-cpp20-backend"

docker build \
  --platform linux/amd64 \
  -t cpp-tutor/opt-cpp-backend-cpp20-sb:local \
  -f "$PROJECT_DIR/local-cpp20-backend/Dockerfile.preserve-display" \
  "$PROJECT_DIR/local-cpp20-backend"
