#!/usr/bin/env zsh
# Run every program in tools/valgrind327-probes through the experimental image
# and flag anomalies. This is the wide net that complements the smoke suite:
# the smoke suite asserts that specific summaries are correct, while this sweeps
# for traces that broke, got truncated, or fell back to raw libstdc++ internals.
#
# Usage: ./tools/probe-valgrind327-edge-cases.sh [probe-name ...]
set -uo pipefail

IMAGE="${CPP_TUTOR_VALGRIND327_IMAGE:-cpp-tutor/opt-cpp-backend-valgrind327-sb:experimental}"
HERE="${0:A:h}"
PROBE_DIR="$HERE/valgrind327-probes"
OUT_DIR="${TMPDIR:-/tmp}/cpp-tutor-valgrind327-probes"
mkdir -p "$OUT_DIR"

if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
  echo "Missing $IMAGE."
  echo "Build it first with ./build-valgrind327-backend.sh."
  exit 1
fi

if [ $# -gt 0 ]; then
  sources=()
  for name in "$@"; do
    sources+=("$PROBE_DIR/$name.cpp")
  done
else
  sources=("$PROBE_DIR"/*.cpp)
fi

for src in $sources; do
  name="${src:t:r}"
  if [ ! -f "$src" ]; then
    echo "no such probe: $name"
    exit 1
  fi
  code="$(cat "$src")"
  docker run --platform linux/amd64 -m 512m --rm \
    --user=netuser --net=none --cap-drop all \
    "$IMAGE" \
    python /tmp/opt-cpp-backend/run_cpp_backend_cpp20_wrapper.py "$code" cpp \
    > "$OUT_DIR/$name.out" 2> "$OUT_DIR/$name.err"
  echo "ran $name"
done

echo
python3 "$HERE/analyze-valgrind327-probes.py" "$PROBE_DIR" "$OUT_DIR"
