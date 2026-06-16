#!/bin/zsh
set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
IMAGE="cpp-tutor/opt-cpp-backend-valgrind327-sb:experimental"

if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
  echo "Missing $IMAGE image."
  echo "Build it first with ./build-valgrind327-backend.sh."
  exit 1
fi

export CPP_TUTOR_CPP_IMAGE="$IMAGE"
exec "$PROJECT_DIR/start-all.sh"
