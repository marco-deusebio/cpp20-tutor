#!/bin/zsh
set -e

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="${1:-$PROJECT_DIR/local-cpp20-backend/valgrind-3.27.1-src}"
IMAGE="${CPP_TUTOR_VALGRIND327_IMAGE:-cpp-tutor/opt-cpp-backend-valgrind327:experimental}"
CID=""

cleanup() {
  if [ -n "$CID" ]; then
    docker rm "$CID" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT INT TERM

if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
  echo "Missing $IMAGE image."
  echo "Build it first with ./build-valgrind327-backend.sh."
  exit 1
fi

mkdir -p "$(dirname "$OUT_DIR")"
rm -rf "$OUT_DIR"

CID="$(docker create --platform linux/amd64 "$IMAGE")"
docker cp "$CID:/tmp/opt-cpp-backend/valgrind-3.27.1" "$OUT_DIR"

echo "Extracted Valgrind 3.27.1 source to $OUT_DIR"
