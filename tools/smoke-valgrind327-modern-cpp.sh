#!/usr/bin/env zsh
set -euo pipefail

IMAGE="${CPP_TUTOR_VALGRIND327_IMAGE:-cpp-tutor/opt-cpp-backend-valgrind327-sb:experimental}"
OUT_DIR="${TMPDIR:-/tmp}/cpp-tutor-valgrind327-modern-smoke"

mkdir -p "$OUT_DIR"

run_case() {
  local name="$1"
  local code="$2"
  local out_file="$OUT_DIR/$name.out"
  local err_file="$OUT_DIR/$name.err"

  docker run --platform linux/amd64 -m 512m --rm \
    --user=netuser --net=none --cap-drop all \
    "$IMAGE" \
    python /tmp/opt-cpp-backend/run_cpp_backend_cpp20_wrapper.py "$code" cpp \
    > "$out_file" 2> "$err_file"

  python3 - "$name" "$out_file" "$err_file" <<'PY'
import json
import sys
from pathlib import Path

name, out_path, err_path = sys.argv[1:]
data = json.loads(Path(out_path).read_text())
trace = data.get("trace")
if not isinstance(trace, list) or not trace:
    raise SystemExit("%s: expected a nonempty trace" % name)
if any(step.get("event") == "uncaught_exception" for step in trace):
    raise SystemExit("%s: compilation or execution failed" % name)

stderr = Path(err_path).read_text()
if "ERROR SUMMARY: 0 errors" not in stderr:
    raise SystemExit("%s: Valgrind did not report a clean run" % name)

if name == "iota":
    encoded_values = []
    for step in trace:
        for frame in step.get("stack_to_render") or []:
            encoded_values.extend((frame.get("encoded_locals") or {}).values())
    rendered = json.dumps(encoded_values)
    for expected in (
        "std::ranges::iota_view<int, int>",
        '"start"',
        '"end"',
        "std::ranges::iota_view::iterator",
        '"current"',
    ):
        if expected not in rendered:
            raise SystemExit("iota: missing summary token %s" % expected)

if name == "compare":
    encoded_values = []
    for step in trace:
        for frame in step.get("stack_to_render") or []:
            encoded_values.extend((frame.get("encoded_locals") or {}).values())
    rendered = json.dumps(encoded_values)
    for expected in (
        "std::strong_ordering",
        "std::weak_ordering",
        "std::partial_ordering",
        '"less"',
        '"equal"',
        '"greater"',
        '"equivalent"',
        '"unordered"',
    ):
        if expected not in rendered:
            raise SystemExit("compare: missing summary token %s" % expected)
    if "_M_value" in rendered:
        raise SystemExit("compare: raw libstdc++ _M_value leaked into trace")

if name == "high_bytes":
    # a char holding a byte >= 0x7f used to emit raw bytes that broke the
    # trace JSON, which dropped every later step
    if len(trace) < 4:
        raise SystemExit("high_bytes: trace was truncated (%d steps)" % len(trace))
    encoded_values = []
    for step in trace:
        for frame in step.get("stack_to_render") or []:
            encoded_values.extend((frame.get("encoded_locals") or {}).values())
    rendered = json.dumps(encoded_values)
    for expected in ('\\\\u00ff', '\\\\u0080', '\\\\u00c8'):
        if expected not in rendered:
            raise SystemExit("high_bytes: missing escaped byte %s" % expected)

if name == "smart_ptrs":
    encoded_values = []
    for step in trace:
        for frame in step.get("stack_to_render") or []:
            encoded_values.extend((frame.get("encoded_locals") or {}).values())
    rendered = json.dumps(encoded_values)
    for expected in (
        "std::unique_ptr<int>",
        "std::shared_ptr<int>",
        "std::weak_ptr<int>",
        '"pointer"',
        '"use_count"',
    ):
        if expected not in rendered:
            raise SystemExit("smart_ptrs: missing summary token %s" % expected)

if name == "containers":
    encoded_values = []
    for step in trace:
        for frame in step.get("stack_to_render") or []:
            encoded_values.extend((frame.get("encoded_locals") or {}).values())
    rendered = json.dumps(encoded_values)
    for expected in (
        "std::vector<int>",
        "std::array<int, 3>",
        "std::pair<int, int>",
        '"capacity"',
        '"elements"',
    ):
        if expected not in rendered:
            raise SystemExit("containers: missing summary token %s" % expected)

if name == "strings":
    encoded_values = []
    for step in trace:
        for frame in step.get("stack_to_render") or []:
            encoded_values.extend((frame.get("encoded_locals") or {}).values())
    rendered = json.dumps(encoded_values)
    for expected in ("std::string", "std::string_view", '"characters"'):
        if expected not in rendered:
            raise SystemExit("strings: missing summary token %s" % expected)

if name == "optional_variant":
    encoded_values = []
    for step in trace:
        for frame in step.get("stack_to_render") or []:
            encoded_values.extend((frame.get("encoded_locals") or {}).values())
    rendered = json.dumps(encoded_values)
    for expected in ("std::optional<int>", '"engaged"', "std::variant<", '"index"'):
        if expected not in rendered:
            raise SystemExit("optional_variant: missing summary token %s" % expected)

if name == "coroutine":
    frame_names = []
    local_names = []
    for step in trace:
        frame_names.append(step.get("func_name", ""))
        for frame in step.get("stack_to_render") or []:
            frame_names.append(frame.get("func_name", ""))
            local_names.extend(frame.get("ordered_varnames") or [])
    if "run() [coroutine body]" not in frame_names:
        raise SystemExit("coroutine: missing normalized coroutine body frame")
    if any(local.startswith("_Coro_") for local in local_names):
        raise SystemExit("coroutine: compiler-generated locals leaked into trace")
    if "promise" not in local_names or "resume_state" not in local_names:
        raise SystemExit("coroutine: missing promise or resume_state")

# No summary should ever expose raw libstdc++ implementation members. A
# leak here means some summary bailed out and fell back to raw internals,
# which is how the unique_ptr summary silently regressed once before.
encoded_blob = json.dumps([
    (frame.get("encoded_locals") or {})
    for step in trace
    for frame in (step.get("stack_to_render") or [])
])
for internal in (
    "_M_dataplus", "_M_head_impl", "_M_elems", "_M_start", "_M_finish",
    "_M_refcount", "_M_index", "_M_engaged", "_M_payload", "__cxx11",
):
    if internal in encoded_blob:
        raise SystemExit("%s: leaked libstdc++ internal %s" % (name, internal))

print("%s: %d trace steps, clean Valgrind run" % (name, len(trace)))
PY
}

run_case native_features $'#include <array>\n#include <bit>\n#include <concepts>\n#include <numbers>\n#include <ranges>\n#include <source_location>\n#include <span>\ntemplate<std::integral T> T twice(T value) { return value + value; }\nint main() {\n  std::array<int, 3> data{1, 2, 3};\n  std::span<int> view(data);\n  auto range = std::views::iota(1, 4);\n  auto where = std::source_location::current();\n  float one = std::bit_cast<float>(0x3f800000u);\n  double pi = std::numbers::pi;\n  int answer = twice(view[1]) + *range.begin() + where.line() + int(one) + int(pi);\n  return answer;\n}'

run_case iota $'#include <ranges>\nint main() {\n  auto nums = std::views::iota(2, 7);\n  auto it = nums.begin();\n  int first = *it;\n  ++it;\n  int second = *it;\n  return second;\n}'

run_case compare $'#include <compare>\n#include <limits>\nint main() {\n  int a = 3;\n  int b = 5;\n  std::strong_ordering less_cmp = a <=> b;\n  std::strong_ordering equal_cmp = a <=> a;\n  std::strong_ordering greater_cmp = b <=> a;\n  double x = 1.5;\n  std::partial_ordering partial_cmp = x <=> 2.5;\n  double nan_value = std::numeric_limits<double>::quiet_NaN();\n  std::partial_ordering unordered_cmp = nan_value <=> x;\n  std::weak_ordering weak_equal = std::weak_ordering::equivalent;\n  std::weak_ordering weak_greater = std::weak_ordering::greater;\n  int total = int(less_cmp < 0) + int(equal_cmp == 0) + int(greater_cmp > 0)\n            + int(partial_cmp < 0) + int(unordered_cmp == std::partial_ordering::unordered)\n            + int(weak_equal == 0) + int(weak_greater > 0);\n  return total;\n}'

run_case high_bytes $'#include <iostream>\nint main() {\n  signed char low = -1;\n  char high = char(0x80);\n  signed char mid = -56;\n  int total = int(low) + int(mid);\n  std::cout << total << std::endl;\n  return 0;\n}'

run_case smart_ptrs $'#include <memory>\nint main() {\n  std::unique_ptr<int> owned(new int(42));\n  std::unique_ptr<int> empty_owner;\n  auto shared = std::make_shared<int>(7);\n  std::weak_ptr<int> observer = shared;\n  int total = *owned + *shared + int(shared.use_count()) + int(bool(empty_owner));\n  return total;\n}'

run_case containers $'#include <array>\n#include <utility>\n#include <vector>\nint main() {\n  std::vector<int> numbers{1, 2, 3};\n  std::array<int, 3> fixed{4, 5, 6};\n  std::pair<int, int> couple{7, 8};\n  numbers.push_back(9);\n  int total = numbers.back() + fixed[0] + couple.first;\n  return total;\n}'

run_case strings $'#include <string>\n#include <string_view>\nint main() {\n  std::string small = "cats";\n  std::string large = "a string comfortably longer than the sso buffer limit";\n  std::string_view view(large);\n  std::string_view slice = view.substr(2, 6);\n  int total = int(small.size() + large.size() + slice.size());\n  return total;\n}'

run_case optional_variant $'#include <optional>\n#include <variant>\nint main() {\n  std::optional<int> engaged = 5;\n  std::optional<int> empty_opt;\n  std::variant<int, double> choice = 3;\n  choice = 2.5;\n  int total = engaged.value_or(0) + empty_opt.value_or(1) + int(choice.index());\n  return total;\n}'

run_case jthread $'#include <stop_token>\n#include <thread>\nint main() {\n  int value = 0;\n  std::jthread worker([&](std::stop_token) { value = 42; });\n  worker.join();\n  return value;\n}'

run_case coroutine $'#include <coroutine>\nstruct task {\n  struct promise_type {\n    task get_return_object() { return {}; }\n    std::suspend_never initial_suspend() { return {}; }\n    std::suspend_never final_suspend() noexcept { return {}; }\n    void return_void() {}\n    void unhandled_exception() {}\n  };\n};\ntask run() { co_return; }\nint main() { auto result = run(); return 0; }'

echo "Modern C++ Valgrind 3.27 smoke passed."
echo "artifacts: $OUT_DIR"
