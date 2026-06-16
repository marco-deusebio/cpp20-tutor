#!/usr/bin/env zsh
set -euo pipefail

IMAGE="${CPP_TUTOR_VALGRIND327_IMAGE:-cpp-tutor/opt-cpp-backend-valgrind327-sb:experimental}"
OUT_FILE="${TMPDIR:-/tmp}/cpp-tutor-valgrind327-smoke.out"
ERR_FILE="${TMPDIR:-/tmp}/cpp-tutor-valgrind327-smoke.err"
CODE=$'int main() {\n  int x = 1;\n  int y = x + 2;\n  return y;\n}'

if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
  echo "Missing Docker image: $IMAGE" >&2
  echo "Build it with ./build-valgrind327-backend.sh" >&2
  exit 2
fi

set +e
docker run --platform linux/amd64 -m 512m --rm \
  --user=netuser --net=none --cap-drop all \
  "$IMAGE" \
  python /tmp/opt-cpp-backend/run_cpp_backend_cpp20_wrapper.py "$CODE" cpp \
  > "$OUT_FILE" 2> "$ERR_FILE"
run_status=$?
set -e

if grep -q "Unknown option: --source-filename=usercode.cpp" "$ERR_FILE"; then
  echo "Valgrind 3.27.1 smoke reached the expected unpatched backend failure."
  echo "stderr: $ERR_FILE"
  echo "stdout: $OUT_FILE"
  exit 0
fi

set +e
trace_summary="$(
  python3 - "$OUT_FILE" <<'PY' 2>/dev/null
import json
import sys
from pathlib import Path

try:
    trace = json.loads(Path(sys.argv[1]).read_text()).get("trace")
except Exception:
    raise SystemExit(1)

if not isinstance(trace, list):
    raise SystemExit(1)

names = []
for step in trace:
    stack = step.get("stack_to_render") or step.get("stack") or []
    for frame in stack:
        for name in frame.get("ordered_varnames") or []:
            if name not in names:
                names.append(name)

print(len(trace))
print(",".join(names))
PY
)"
trace_parse_status=$?
set -e

if [[ "$trace_parse_status" -eq 0 && -n "$trace_summary" ]]; then
  trace_len="${trace_summary%%$'\n'*}"
  ordered_names="${trace_summary#*$'\n'}"
  if [[ "$ordered_names" == "$trace_summary" ]]; then
    ordered_names=""
  fi
  if [[ "$trace_len" -gt 0 ]]; then
    echo "Valgrind 3.27.1 smoke produced trace JSON with $trace_len step(s)."
    if [[ -n "$ordered_names" ]]; then
      echo "ordered locals observed: $ordered_names"
    else
      echo "ordered locals observed: none yet"
    fi
  else
    echo "Valgrind 3.27.1 smoke accepted cpp-tutor flags but produced an empty trace."
    echo "Next patch target: Memcheck IR instrumentation and .vgtrace emission."
  fi
  echo "stdout: $OUT_FILE"
  echo "stderr: $ERR_FILE"
  exit 0
fi

echo "Valgrind 3.27.1 smoke ended with unexpected status $run_status." >&2
echo "stderr: $ERR_FILE" >&2
echo "stdout: $OUT_FILE" >&2
exit 1
