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
        "std::array<int, 0>",
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

if name == "wide_strings":
    encoded_values = []
    for step in trace:
        for frame in step.get("stack_to_render") or []:
            encoded_values.extend((frame.get("encoded_locals") or {}).values())
    rendered = json.dumps(encoded_values)
    for expected in (
        "std::u16string",
        "std::u32string",
        "std::u16string_view",
        "std::string_view",
    ):
        if expected not in rendered:
            raise SystemExit("wide_strings: missing summary token %s" % expected)
    # a wide buffer must never be decoded one byte per character
    for value in encoded_values:
        if not isinstance(value, list) or len(value) < 3:
            continue
        if value[2] not in ("std::u16string", "std::u32string",
                            "std::u16string_view"):
            continue
        fields = [f[0] for f in value[3:] if isinstance(f, list) and f]
        if "characters" in fields:
            raise SystemExit(
                "wide_strings: %s decoded characters as single bytes" % value[2])

if name == "float_values":
    encoded_values = []
    for step in trace:
        for frame in step.get("stack_to_render") or []:
            encoded_values.extend((frame.get("encoded_locals") or {}).values())
    rendered = json.dumps(encoded_values)
    # Valgrind's own %f truncated at six decimals and mangled the extremes,
    # so these exact spellings are the point of the bit-pattern encoding
    for expected in (
        "1e-10",
        "0.123456789012345",
        '"NaN"',
        '"Infinity"',
        "2.5",
    ):
        if expected not in rendered:
            raise SystemExit("float_values: missing %s" % expected)
    if "0.333333," in rendered or "0.333333]" in rendered:
        raise SystemExit("float_values: double truncated to six decimals")

if name == "assoc_containers":
    encoded_values = []
    for step in trace:
        for frame in step.get("stack_to_render") or []:
            encoded_values.extend((frame.get("encoded_locals") or {}).values())
    rendered = json.dumps(encoded_values)
    for expected in ("std::map<std::string, int>", "std::set<int>", '"size"'):
        if expected not in rendered:
            raise SystemExit("assoc_containers: missing summary token %s" % expected)
    if "_Rb_tree" in rendered:
        raise SystemExit("assoc_containers: raw _Rb_tree internals leaked into trace")

if name == "chrono":
    encoded_values = []
    for step in trace:
        for frame in step.get("stack_to_render") or []:
            encoded_values.extend((frame.get("encoded_locals") or {}).values())
    rendered = json.dumps(encoded_values)
    for expected in (
        "std::chrono::milliseconds",
        "std::chrono::seconds",
        '"count"',
        "std::chrono::time_point<",
        '"time_since_epoch"',
    ):
        if expected not in rendered:
            raise SystemExit("chrono: missing summary token %s" % expected)

if name == "bitset_atomic_byte":
    encoded_values = []
    for step in trace:
        for frame in step.get("stack_to_render") or []:
            encoded_values.extend((frame.get("encoded_locals") or {}).values())
    rendered = json.dumps(encoded_values)
    for expected in (
        "std::bitset<8>",
        '"bits"',
        "std::atomic<int>",
        "std::byte",
    ):
        if expected not in rendered:
            raise SystemExit("bitset_atomic_byte: missing token %s" % expected)

if name == "complex_span_tuple":
    encoded_values = []
    for step in trace:
        for frame in step.get("stack_to_render") or []:
            encoded_values.extend((frame.get("encoded_locals") or {}).values())
    rendered = json.dumps(encoded_values)
    for expected in (
        "std::complex<double>",
        '"real"',
        '"imag"',
        "std::span<int>",
        "std::tuple<int, double>",
    ):
        if expected not in rendered:
            raise SystemExit("complex_span_tuple: missing token %s" % expected)

if name == "stdlib_misc":
    encoded_values = []
    for step in trace:
        for frame in step.get("stack_to_render") or []:
            encoded_values.extend((frame.get("encoded_locals") or {}).values())
    rendered = json.dumps(encoded_values)
    for expected in (
        "std::any",
        '"has_value"',
        "std::filesystem::path",
        "std::error_code",
        "std::reference_wrapper<int>",
    ):
        if expected not in rendered:
            raise SystemExit("stdlib_misc: missing token %s" % expected)
    # an engaged std::any must report true at some point before destruction
    if '"has_value", ["C_DATA"' in rendered and "true" not in rendered:
        raise SystemExit("stdlib_misc: std::any never reported an engaged value")

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
    "_M_string_length", "_M_local_buf", "_Rb_tree",
    # raw float bit tags must always be decoded before reaching the trace
    "f32:", "f64:",
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

run_case containers $'#include <array>\n#include <utility>\n#include <vector>\nint main() {\n  std::vector<int> numbers{1, 2, 3};\n  std::array<int, 3> fixed{4, 5, 6};\n  std::array<int, 0> nothing{};\n  std::pair<int, int> couple{7, 8};\n  numbers.push_back(9);\n  int total = numbers.back() + fixed[0] + couple.first + int(nothing.size());\n  return total;\n}'

run_case strings $'#include <string>\n#include <string_view>\nint main() {\n  std::string small = "cats";\n  std::string large = "a string comfortably longer than the sso buffer limit";\n  std::string_view view(large);\n  std::string_view slice = view.substr(2, 6);\n  int total = int(small.size() + large.size() + slice.size());\n  return total;\n}'

run_case optional_variant $'#include <optional>\n#include <variant>\nint main() {\n  std::optional<int> engaged = 5;\n  std::optional<int> empty_opt;\n  std::variant<int, double> choice = 3;\n  choice = 2.5;\n  int total = engaged.value_or(0) + empty_opt.value_or(1) + int(choice.index());\n  return total;\n}'

run_case chrono $'#include <chrono>\nint main() {\n  std::chrono::milliseconds ms(250);\n  std::chrono::seconds sec(3);\n  std::chrono::steady_clock::time_point tp{};\n  long total = ms.count() + sec.count() + tp.time_since_epoch().count();\n  return int(total);\n}'

run_case bitset_atomic_byte $'#include <atomic>\n#include <bitset>\n#include <cstddef>\nint main() {\n  std::bitset<8> flags(11);\n  std::atomic<int> counter(5);\n  std::byte raw{42};\n  int total = int(flags.count()) + counter.load() + int(raw);\n  return total;\n}'

run_case complex_span_tuple $'#include <complex>\n#include <span>\n#include <tuple>\n#include <vector>\nint main() {\n  std::complex<double> z(1.5, -2.25);\n  std::vector<int> data{1, 2, 3};\n  std::span<int> view(data);\n  std::tuple<int, double> row{4, 5.5};\n  int total = int(z.real()) + int(view.size()) + std::get<0>(row);\n  return total;\n}'

run_case stdlib_misc $'#include <any>\n#include <filesystem>\n#include <functional>\n#include <system_error>\nint main() {\n  std::any boxed = 42;\n  std::any empty_any;\n  std::filesystem::path p("/tmp/demo.txt");\n  std::error_code ec = std::make_error_code(std::errc::invalid_argument);\n  int backing = 7;\n  std::reference_wrapper<int> ref(backing);\n  int total = int(boxed.has_value()) + int(empty_any.has_value()) + ref.get();\n  return total;\n}'

run_case float_values $'#include <limits>\nint main() {\n  double tiny = 1e-10;\n  double precise = 0.123456789012345;\n  double third = 1.0 / 3.0;\n  double nan_v = std::numeric_limits<double>::quiet_NaN();\n  double inf_v = std::numeric_limits<double>::infinity();\n  float single = 2.5f;\n  return int(tiny + precise + third + single);\n}'

run_case wide_strings $'#include <string>\n#include <string_view>\nint main() {\n  std::u16string wide = u"ab";\n  std::u32string wider = U"cd";\n  std::string plain = "ef";\n  std::string_view plain_view(plain);\n  std::u16string_view wide_view(wide);\n  int total = int(wide.size() + wider.size() + plain.size() + wide_view.size());\n  return total;\n}'

run_case assoc_containers $'#include <map>\n#include <set>\n#include <string>\nint main() {\n  std::map<std::string, int> ages;\n  ages["ada"] = 36;\n  ages["alan"] = 41;\n  std::set<int> ids;\n  ids.insert(7);\n  ids.insert(9);\n  int total = int(ages.size()) + int(ids.size());\n  return total;\n}'

run_case jthread $'#include <stop_token>\n#include <thread>\nint main() {\n  int value = 0;\n  std::jthread worker([&](std::stop_token) { value = 42; });\n  worker.join();\n  return value;\n}'

run_case coroutine $'#include <coroutine>\nstruct task {\n  struct promise_type {\n    task get_return_object() { return {}; }\n    std::suspend_never initial_suspend() { return {}; }\n    std::suspend_never final_suspend() noexcept { return {}; }\n    void return_void() {}\n    void unhandled_exception() {}\n  };\n};\ntask run() { co_return; }\nint main() { auto result = run(); return 0; }'

echo "Modern C++ Valgrind 3.27 smoke passed."
echo "artifacts: $OUT_DIR"
