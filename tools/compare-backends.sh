#!/usr/bin/env zsh
# Run the same programs through the stable Valgrind 3.11 backend and the
# experimental Valgrind 3.27 backend, then compare the traces.
#
# This is step 5 of the porting checklist in VALGRIND327-EXPERIMENT.md:
# compare trace shape against cpp-tutor/opt-cpp-backend-cpp20-sb:local.
#
# Usage: ./tools/compare-backends.sh [probe-name ...]
set -uo pipefail

STABLE_IMAGE="${CPP_TUTOR_STABLE_IMAGE:-cpp-tutor/opt-cpp-backend-cpp20-sb:local}"
EXPERIMENTAL_IMAGE="${CPP_TUTOR_VALGRIND327_IMAGE:-cpp-tutor/opt-cpp-backend-valgrind327-sb:experimental}"
HERE="${0:A:h}"
PROBE_DIR="$HERE/valgrind327-probes"
OUT_DIR="${TMPDIR:-/tmp}/cpp-tutor-backend-comparison"
mkdir -p "$OUT_DIR"

for image in "$STABLE_IMAGE" "$EXPERIMENTAL_IMAGE"; do
  if ! docker image inspect "$image" >/dev/null 2>&1; then
    echo "Missing $image."
    echo "Build the stable backend with ./build-cpp20-backend.sh and the"
    echo "experimental backend with ./build-valgrind327-backend.sh."
    exit 1
  fi
done

run_backend() {
  local image="$1" name="$2" code="$3" tag="$4"
  docker run --platform linux/amd64 -m 512m --rm \
    --user=netuser --net=none --cap-drop all \
    "$image" \
    python /tmp/opt-cpp-backend/run_cpp_backend_cpp20_wrapper.py "$code" cpp \
    > "$OUT_DIR/$name.$tag.out" 2> "$OUT_DIR/$name.$tag.err"
}

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
  run_backend "$STABLE_IMAGE" "$name" "$code" stable
  run_backend "$EXPERIMENTAL_IMAGE" "$name" "$code" experimental
  echo "compared $name"
done

echo
python3 "$HERE/analyze-backend-comparison.py" "$PROBE_DIR" "$OUT_DIR"
