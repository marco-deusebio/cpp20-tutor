# Valgrind 3.27 Backend Experiment

This is a separate experimental backend line for trying to move cpp-tutor's
C/C++ tracer from the patched Valgrind 3.11.0 backend to Valgrind 3.27.1.

## Images

- `cpp-tutor/opt-cpp-backend-valgrind327:experimental`
- `cpp-tutor/opt-cpp-backend-valgrind327-sb:experimental`

Build with:

```sh
./build-valgrind327-backend.sh
```

The `-sb` image reuses the current local preserve-display wrapper from
`cpp-tutor/opt-cpp-backend-cpp20-sb:local`.
The experimental Dockerfile also applies postprocessor patches from
`local-cpp20-backend/patches/opt-backend/*.patch` after cloning
`opt-cpp-backend` and after the Valgrind build layer, so postprocessor-only
changes can usually rebuild without recompiling Valgrind.

## Current Result

Valgrind 3.27.1 builds and runs in the experimental Docker image with the
cpp-tutor trace flags restored. The current patch stack emits valid
step-by-step trace JSON with stdout, source line/function metadata, and stack
frames. The latest verified wrapper image is
`sha256:b3cf5b3445fef1897713c9367b137e0673510d0e6c35ace31c58157a46a83f64`
from the `2026-06-16` rebuild that renders clean `std::optional<T>`
summaries, conservative `std::variant<T...>` active-alternative summaries, and
small-string active alternatives inside `std::variant<int, std::string>`, plus
source-level `std::weak_ptr<T>`, `std::span<T>`, `std::string_view`, and
`std::chrono` duration/time-point summaries, `std::bitset<N>` summaries, and
`std::atomic<T>` summaries, and `std::initializer_list<T>` summaries.

The image is still a patch-porting sandbox rather than a drop-in replacement
for the stable local backend. The latest source-side patch adds an incremental
direct DWARF variable traversal path for stack-frame scalar locals, exposing
Memcheck's definedness check and serializing base/enum local values into each
frame's `encoded_locals` and `ordered_varnames` fields after postprocessing.
Pointer/reference locals now render their raw address values, and bounded
zero-based stack arrays now render as cpp-tutor `C_ARRAY` values. Simple C++
struct/class locals now render as cpp-tutor `C_STRUCT` values, including
nested structs/classes whose members use direct field offsets. `char*` and
`const char*` values that point at a bounded null-terminated character sequence
now emit a `deref_val` heap-block payload, which lets the existing
postprocessor render string literals and pointer-to-suffix cases as `C_ARRAY`
character entries. Top-level typed pointers into Valgrind-described heap
blocks now emit one-level `deref_val` heap-block payloads for scalar, array,
and struct/class pointees, capped at 256 displayed elements and trimmed at the
first unallocated element. This is still narrower than the old cpp-tutor
pretty-printer. Source-side postprocessor patches now recognize libstdc++
`std::string` objects, hide `_M_dataplus` internals, and render each string as
a `std::string` pointer-like value whose heap character buffer still updates
step by step. The Valgrind-side struct serializer now also attempts to flatten
unnamed/inherited struct fields, continuation types, and DWARF inheritance
entries before postprocessing. With that inheritance metadata exposed, a
postprocessor patch can summarize libstdc++ `std::vector<T>` control blocks as
`std::vector<T>` structs with `size`, `capacity`, `data`, and active `elements`
fields for scalar and simple struct/class element buffers whose `_M_start`
pointer includes a bounded heap dereference payload. Vector element display
names now collapse known libstdc++ string spellings to `std::string`, so
`std::vector<std::string>` renders as the source-level type instead of
`std::vector<std::__cxx11::basic_string<...>>`. `std::array<T, N>` now renders
as a fixed-size container with `size` and `elements`, avoiding the raw `_M_elems`
implementation wrapper. `std::pair<T, U>` now renders with clean source-level
template names and its existing `first`/`second` values. `std::unique_ptr<T>`
now renders as a source-level smart pointer summary with a `pointer` field and,
when Valgrind emitted a bounded heap dereference for the owned object, a
`pointee` field for scalar, simple struct/class, and currently pointer-style
`std::string` pointees. The postprocessor now also preserves duplicate raw
JSON member keys emitted by libstdc++ tuple leaves, so `std::tuple<T...>` can
render with clean source-level element indexes, a `size` field, and scalar,
`std::string`, or simple struct/class element values. `std::shared_ptr<T>` now
renders a source-level smart pointer summary with `pointer`, `use_count`, and,
when the stored pointer's heap payload is available, `pointee` fields for
scalar, simple struct/class, and currently pointer-style `std::string`
pointees. The Valgrind-side union field support now exposes raw libstdc++
`std::optional` payload storage (`_M_value`) and `std::variant` alternative
storage (`_M_u`, `_M_first`, `_M_rest`, `_M_index`) to the postprocessor.
Postprocessor summaries now render `std::optional<T>` with `engaged` and
`value` fields for scalar, simple struct/class, and pointer-style
`std::string` payloads. `std::variant<T...>` now renders its source-level
template name, active `index`, active type, and only the selected alternative
instead of every overlapping union branch. Active `std::string` alternatives
stored in libstdc++ aligned in-place storage now decode to the same
pointer-style `std::string` summary shape backed by a heap character array for
small-string values. `std::weak_ptr<T>` now renders with source-level type
names, stored pointer, live `use_count`, and a best-effort `pointee` when
Valgrind emitted a bounded dereference payload for `_M_ptr`. `std::span<T>` now
renders with source-level type names, `data`, `size`, and active `elements`
when the span data pointer has an emitted heap dereference payload. Stack-backed
spans still show `data` and `size`, while their viewed stack elements remain
visible through the backing array local. `std::string_view` now renders with
source-level type names, `data`, `size`, and non-null-terminated sliced
`characters` when the view pointer has an emitted character dereference
payload. `std::chrono::duration` values now render with source-level duration
names and `count`, and `std::chrono::time_point` values render with a
source-level clock/duration type plus a nested `time_since_epoch` duration.
`std::bitset<N>` now renders with source-level type names, fixed `size`, raw
storage `value`, and per-bit entries for bitsets up to 256 bits.
`std::atomic<T>` now renders with source-level type names and a clean `value`
field for libstdc++ atomics backed by scalar `_M_i` storage.
`std::initializer_list<T>` now renders with source-level type names plus
`data` and `size` fields instead of raw `_M_array` / `_M_len` internals.
Nested heap pointers, non-SSO variant string payloads, broader variant
alternative shapes, general C++ container internals, non-null-terminated
non-view character buffers, bitfields, fuller inherited/base-class layout
details, and some static-local/global edge cases still need additional
forward-port work.
Top-level globals in the active user debug object now render into
`globals`/`ordered_globals` using the same scalar, pointer, array, and
struct/class encoders as locals.

The backend invocation must include `--read-var-info=yes`; without it, Valgrind
3.27.1 still produces step traces but does not load the DWARF variable metadata
needed by the local traversal patch.

## Local Tools

- `tools/extract-valgrind327-source.sh` extracts the built 3.27.1 source tree
  from the experimental image into `local-cpp20-backend/valgrind-3.27.1-src`.
  That directory is generated local inspection output and is intentionally
  ignored by git.
- `tools/valgrind327-patch-anchors.py` compares the old patched Valgrind
  3.11.0 source against the extracted 3.27.1 source and prints likely
  forward-port anchors.
- `tools/smoke-valgrind327-backend.sh` runs a tiny multiline C++ program
  through the experimental wrapper image. It reports whether the image is still
  at the old unknown-option baseline, has advanced to trace emission, and
  whether ordered local variable names are visible yet.

## Patch Surface

The old cpp-tutor Valgrind patch is broader than command-line parsing. It adds
trace options, redirects stdout, injects an instruction hook in Memcheck's IR
translation path, and walks debug metadata to serialize local/global variables.

Primary files to forward-port:

- `memcheck/mc_include.h`
- `memcheck/mc_main.c`
- `memcheck/mc_translate.c`
- `include/pub_tool_debuginfo.h`
- `coregrind/m_debuginfo/debuginfo.c`

Useful 3.27.1 anchors found so far:

- `memcheck/mc_main.c`: `LeakCheckMode MC_(clo_leak_check)` near line 6069,
  `mc_process_cmd_line_options` near line 6100, `mc_post_clo_init` near line
  8185, and `mc_fini` near line 8460.
- `memcheck/mc_translate.c`: `Ist_IMark` cases near lines 8005, 8460, 8793,
  8970, 9028, and 9092.
- `include/pub_tool_debuginfo.h` and `coregrind/m_debuginfo/debuginfo.c` still
  expose the `StackBlock`, `GlobalBlock`, and
  `VG_(di_get_global_blocks_from_dihandle)` structures/functions the old
  variable traversal code was built around.

Tracked Valgrind patches live in
`local-cpp20-backend/patches/valgrind327/*.patch`. The experimental Dockerfile
applies any patches in that directory before configuring/building Valgrind.

Current tracked patches:

- `0001-cpp-tutor-trace-options.patch`: ports the cpp-tutor
  `--source-filename` and `--trace-filename` options, trace file handle, and
  stdout redirection into Valgrind 3.27.1. This gets the backend past the
  custom-option parse failure.
- `0002-cpp-tutor-minimal-step-trace.patch`: ports a minimal Memcheck
  `Ist_IMark` instruction hook that emits valid `.vgtrace` records with
  stdout, line/function metadata, and stack frames. This enables basic
  step-by-step line visualization, but locals/globals are intentionally empty
  until the debug-info variable traversal patch is ported.
- `0003-cpp-tutor-variable-name-discovery.patch`: adds full-name fields to
  Valgrind 3.27.1 `StackBlock` / `GlobalBlock` summaries and has the minimal
  trace emitter write `ordered_varnames` from `VG_(di_get_stack_blocks_at_ip)`.
  This compiles in the experimental image, but smoke still reports no scalar
  locals. Treat it as plumbing for the deeper traversal port, not final variable
  visualization support.
- `0004-cpp-tutor-direct-scalar-locals.patch`: exposes Memcheck's
  `is_mem_defined` helper and adds a direct in-scope DWARF variable walk in
  `coregrind/m_debuginfo/debuginfo.c`. It evaluates each local variable's
  location expression with the traced frame's IP/SP/FP and emits minimal JSON
  for defined, uninitialized, or unallocated scalar base/enum locals. This is
  the first value-serialization slice for step-by-step variable visualization
  on Valgrind 3.27.x; complex C++ object rendering remains future work.
- `0005-cpp-tutor-pointer-array-locals.patch`: extends the direct local
  serializer to pointer/reference variables and bounded stack arrays. Pointers
  render as raw address values; arrays render recursively with cpp-tutor's
  existing array JSON shape. This intentionally avoids heap/string dereference
  and caps array expansion at 256 elements.
- `0006-cpp-tutor-struct-locals.patch`: extends the direct local serializer to
  complete C++ struct/class variables. It emits cpp-tutor `C_STRUCT` payloads
  for named direct-offset fields, recursing through nested struct/class fields
  and existing scalar/pointer/array serializers. It intentionally skips unions,
  bitfields, dynamic field locations, inherited/base-class layout details, and
  caps field expansion at 128 fields.
- `0007-cpp-tutor-global-vars.patch`: emits top-level globals for the active
  user debug object into each trace record's `globals` and `ordered_globals`
  fields. Global scalar, array, pointer/reference, and struct/class values
  reuse the same direct DWARF serializer as locals. This intentionally does not
  attempt the old backend's function-scope static variable fallback yet and
  caps global expansion at 256 variables.
- `0008-cpp-tutor-c-string-pointer-deref.patch`: extends pointer/reference
  serialization for resolved `char` pointees. If the pointee address contains a
  defined null-terminated character sequence within 256 bytes, the pointer
  includes a `deref_val` heap-block payload. The postprocessor then places that
  payload into `heap`, so string literals such as `const char* msg = "hey"` and
  suffix pointers such as `msg + 1` render as character arrays. The Valgrind
  emitter also escapes arbitrary control bytes as JSON unicode escapes, which
  keeps library-managed character buffers parseable even when they contain
  non-printable bookkeeping bytes.
- `0009-cpp-tutor-heap-pointer-deref.patch`: extends pointer/reference
  serialization for non-character pointees. If a top-level pointer refers into
  a Valgrind-described heap allocation, the pointer includes a one-level
  `deref_val` heap-block payload whose elements reuse the scalar, array, and
  struct/class serializers. Expansion is capped at 256 elements, stops at the
  first unallocated element to avoid allocator-padding noise, and intentionally
  does not recursively dereference nested pointers.
- `0010-cpp-tutor-inherited-struct-fields.patch`: factors direct struct/class
  member emission through a recursive helper that flattens unnamed struct
  fields and follows Valgrind `TyStOrUn.typeR` continuation types. This is
  infrastructure for inherited/base storage layouts and keeps ordinary
  direct-field structs working, but it does not by itself expose libstdc++
  `std::vector` internals in Valgrind 3.27.1 traces.
- `0011-cpp-tutor-inheritance-fields.patch`: teaches the Valgrind 3.27.1 DWARF
  reader to keep `DW_TAG_inheritance` entries as anonymous fields on
  struct/class types. Combined with the `0010` serializer flattening, this
  exposes inherited libstdc++ storage bases such as `std::vector`'s `_M_impl`
  control block to the trace postprocessor.
- `0012-cpp-tutor-struct-field-heap-deref.patch`: carries the existing
  one-level heap dereference permission through struct/class field emission.
  This lets top-level objects with pointer fields, including libstdc++
  `std::vector<T>` control blocks, expose bounded heap payloads for their data
  pointers without recursively dereferencing nested pointers.
- `0013-cpp-tutor-union-fields.patch`: teaches the Valgrind 3.27.1 DWARF reader
  to keep union members with no explicit `DW_AT_data_member_location` as
  zero-offset fields, then lets the direct serializer emit complete unions.
  This exposes libstdc++ union-backed storage used by `std::optional<T>` and
  `std::variant<T...>` to the postprocessor.

Postprocessor patches live in
`local-cpp20-backend/patches/opt-backend/*.patch` and are applied to the cloned
`opt-cpp-backend` source after the Valgrind/runner patch layer:

- `0001-cpp-tutor-std-string-postprocess.patch`: collapses libstdc++
  `basic_string<char>` internals into a clean `std::string` scalar value while
  preserving the emitted heap character buffer for step-by-step visualization.
- `0002-cpp-tutor-quiet-to-delete-debug.patch`: removes the old diagnostic
  `to_delete:` stderr prints for filtered static-initializer and redundant
  trace records while preserving the actual filtering behavior.
- `0003-cpp-tutor-std-vector-summary.patch`: adds helpers that recognize
  libstdc++ `std::vector<T>` control blocks, infer `size` and `capacity` from
  `_M_start`, `_M_finish`, and `_M_end_of_storage`, and build a cleaner
  `std::vector<T>` summary shape.
- `0004-cpp-tutor-use-std-vector-summary.patch`: invokes the vector summary
  helper before falling back to raw `C_STRUCT` member rendering.
- `0005-cpp-tutor-std-vector-elements.patch`: uses `_M_start`'s emitted
  `deref_val` heap block, when available, to add an active `elements` `C_ARRAY`
  to the clean `std::vector<T>` summary. The array is sliced to `size`, so
  spare capacity does not render as initialized vector elements.
- `0006-cpp-tutor-std-vector-struct-elements.patch`: infers vector element byte
  size from emitted trace values when the C++ type is not one of the known
  primitive sizes. This lets vectors of simple user-defined structs/classes,
  such as `std::vector<Point>`, compute `size`/`capacity` and render structured
  active elements.
- `0007-cpp-tutor-std-vector-display-types.patch`: normalizes known noisy
  libstdc++ element type names in vector summaries. In particular,
  `std::__cxx11::basic_string<char, ...>` displays as `std::string`, yielding
  cleaner `std::vector<std::string>` visualizations.
- `0008-cpp-tutor-std-array-summary.patch`: recognizes libstdc++
  `std::array<T, N>` objects, encodes their `_M_elems` storage as the usual
  `C_ARRAY`, and returns a cleaner summary with fixed `size` and `elements`
  fields.
- `0009-cpp-tutor-std-pair-summary.patch`: recognizes libstdc++ `std::pair<T, U>`
  objects with visible `first` and `second` fields, normalizes noisy template
  arguments such as libstdc++ string spellings, and returns a clean
  `std::pair<T, U>` summary.
- `0010-cpp-tutor-std-unique-ptr-summary.patch`: recognizes libstdc++
  `std::unique_ptr<T>` control blocks, extracts the nested stored pointer from
  `_M_head_impl`, and returns a clean smart-pointer summary with `pointer` and
  optional `pointee` fields.
- `0011-cpp-tutor-std-tuple-summary.patch`: preserves duplicate JSON keys such
  as repeated `_M_head_impl` tuple leaves, then recognizes libstdc++
  `std::tuple<T...>` objects and renders a clean summary with `size` and
  source-order numeric element fields.
- `0012-cpp-tutor-std-shared-ptr-summary.patch`: recognizes libstdc++
  `std::shared_ptr<T>` objects, extracts `_M_ptr`, finds `_M_use_count` through
  the shared control block heap payload, and renders a clean summary with
  `pointer`, optional `use_count`, and optional `pointee` fields.
- `0013-cpp-tutor-shared-ptr-string-pointee.patch`: reuses the existing
  `std::string` postprocessor summary when a `std::shared_ptr<std::string>`
  points inside a combined `make_shared` heap allocation, replacing the raw
  unsupported anonymous field with a clean pointer-style string pointee.
- `0014-cpp-tutor-std-optional-summary.patch`: recognizes libstdc++
  `std::optional<T>` wrappers now that union-backed `_M_value` storage is
  visible, and returns a compact source-level summary with `engaged` and
  `value` fields.
- `0015-cpp-tutor-std-variant-summary.patch`: recognizes libstdc++
  `std::variant<T...>` wrappers, uses `_M_index` to choose the active
  `_M_first` alternative through the nested `_M_rest` union chain, and returns
  a conservative summary with `index`, `active_type`, and the selected value.
- `0016-cpp-tutor-std-variant-string-summary.patch`: adds byte-array helpers
  for libstdc++ in-place string storage inside variant alternatives, including
  tolerant handling for uninitialized spare small-string capacity.
- `0017-cpp-tutor-use-variant-string-summary.patch`: invokes the in-place
  string decoder when the selected variant alternative is `std::string`.
- `0018-cpp-tutor-relax-variant-string-storage.patch`: relaxes the helper's
  type-name guard so the decoder relies on the already-selected active
  `std::string` alternative plus the observed storage layout.
- `0019-cpp-tutor-std-weak-ptr-summary.patch`: recognizes libstdc++
  `std::weak_ptr<T>` objects, extracts `_M_ptr`, finds `_M_use_count` through
  the weak reference-count control block, and renders a clean summary with
  `pointer`, optional `use_count`, and optional `pointee` fields.
- `0020-cpp-tutor-std-span-summary.patch`: recognizes libstdc++ `std::span<T>`
  objects, hides `_M_extent` / `_M_ptr` internals, normalizes dynamic extent to
  `std::span<T>`, and renders `data`, `size`, plus sliced `elements` when the
  span points at a bounded heap dereference payload.
- `0021-cpp-tutor-std-string-view-summary.patch`: recognizes libstdc++
  `std::basic_string_view<char>` objects, hides `_M_len` / `_M_str` internals,
  and renders `data`, `size`, plus sliced `characters` without requiring a
  null terminator.
- `0022-cpp-tutor-std-chrono-summary.patch`: recognizes libstdc++
  `std::chrono::duration` and `std::chrono::time_point` objects, normalizes
  common duration aliases such as `milliseconds` and `seconds`, and renders
  `count` or nested `time_since_epoch` summaries instead of raw `__r` / `__d`
  fields.
- `0023-cpp-tutor-std-bitset-summary.patch`: recognizes libstdc++
  `std::bitset<N>` objects, hides raw `_M_w` storage behind a source-level
  summary, and renders `size`, storage `value`, and per-bit boolean entries
  for bitsets up to 256 bits.
- `0024-cpp-tutor-std-atomic-summary.patch`: recognizes libstdc++
  `std::atomic<T>` objects backed by scalar `_M_i` storage and renders a clean
  source-level summary with a single `value` field.
- `0025-cpp-tutor-std-initializer-list-summary.patch`: recognizes libstdc++
  `std::initializer_list<T>` objects, hides raw `_M_array` / `_M_len` internals,
  and renders source-level `data` and `size` fields, plus `elements` when the
  pointer has a bounded dereference payload.

## Porting Checklist

1. Identify the cpp-tutor modifications in `valgrind-3.11.0` that add:
   - `--source-filename`
   - `--trace-filename`
   - `.vgtrace` event emission consumed by `vg_to_opt_trace.py`
2. Forward-port those modifications onto `valgrind-3.27.1`.
   - Done: custom trace options and trace/stdout file setup.
   - Done: minimal `memcheck/mc_translate.c` instruction hook and `.vgtrace`
     step emission.
   - Done: stack/global block full-name plumbing.
   - Done: direct scalar local traversal and value serialization for base/enum
     locals.
   - Done: direct pointer/reference locals and bounded stack-array
     serialization.
   - Done: simple and nested struct/class local serialization for direct-offset
     fields.
   - Done: bounded null-terminated `char*` / `const char*` string pointer
     dereference into postprocessed `heap` character arrays.
   - Done: one-level typed heap pointer dereference for top-level scalar,
     array, and struct/class pointees.
   - Done: libstdc++ `std::string` postprocessing into cleaner visual values
     backed by step-by-step heap character arrays.
   - Done: inherited/unnamed struct-field traversal infrastructure for the
     Valgrind 3.27.x serializer.
   - Done: DWARF inheritance entries are preserved as anonymous fields, which
     exposes inherited libstdc++ control blocks such as `std::vector`'s
     `_M_impl`.
   - Done: DWARF union members with no explicit location are preserved as
     zero-offset fields, which exposes raw libstdc++ `std::optional<T>` and
     `std::variant<T...>` payload storage.
   - Done: libstdc++ `std::vector<T>` postprocessing into a cleaner summary
     with `size`, `capacity`, and `data` fields when the control-block pointers
     are available.
   - Done: one-level heap dereference now propagates through struct/class
     fields, enabling `std::vector<int>` summaries to show active indexed
     element values.
   - Done: vector element-size inference from trace payloads enables
     `std::vector<Point>` summaries to show active structured element values.
   - Next: richer local/global variable serialization for nested heap pointers,
     smart pointer/container summaries, bitfields,
     inherited/base-class details, and function-scope static variable edge
     cases.
3. Rebuild `cpp-tutor/opt-cpp-backend-valgrind327:experimental`.
4. Run a simple backend smoke test and confirm `usercode.vgtrace` is produced.
   - Done: smoke produces a 4-step trace for a tiny multiline `main`.
   - Done: smoke observes scalar locals `x,y`; the final JSON shows `x` moving
     from `<UNINITIALIZED>` to `1` and `y` moving from `<UNINITIALIZED>` to `3`.
   - Done: an additional C++20 scalar probe with structured bindings,
     `enum class`, and `double` locals shows `a,b,c,d` in `main` frames, with
     values progressing to `4`, `5`, `2`, and `9.5`.
   - Done: pointer/array probe shows `nums` as a `C_ARRAY` with elements
     `1,2,3`, `p` as a pointer to the middle element address, and `total`
     progressing to `8`.
   - Done: struct/class probe shows `p` as a `Point` `C_STRUCT`, `b` as a
     nested `Box` `C_STRUCT` containing `origin`, `width`, and `height`, and
     `total` progressing to `15`.
   - Done: global probe shows `ordered_globals` with `global_total`,
     `global_values`, and `global_counter`; the final JSON shows
     `global_total` moving from `10` to `12`, `global_counter.current` moving
     from `4` to `6`, and stdout reaching `18`.
   - Done: string pointer probe shows `msg` as a pointer to a heap `C_ARRAY`
     containing `h,e,y,\0`, `later = msg + 1` as a pointer to the suffix
     `e,y,\0`, and stdout reaching `hey`.
   - Done: heap pointer probe shows `new int(7)` as a one-element heap
     `C_ARRAY`, `new Point{2,5}` as a one-element heap `C_ARRAY` containing a
     `Point` `C_STRUCT`, `new int[3]{1,2,3}` as a three-element heap
     `C_ARRAY`, and stdout reaching `16`.
   - Done: `std::string` mutation probe shows `shorty` and `longer` as clean
     `std::string` values backed by heap character arrays, with `shorty`
     changing from `cat` to `cats`, `longer` changing from `hippopotamus` to
     `Hippopotamus`, and stdout reaching `cats Hippopotamus`.
   - Done: the same `std::string` probe no longer emits old `to_delete:`
     postprocessor diagnostics on stderr; postprocess stderr is empty while
     Valgrind still reports zero errors.
   - Done: C++20 string predicate probe rewrites `starts_with`, `ends_with`,
     and `contains`; locals `a`, `b`, and `c` progress to `1`, and stdout
     reaches `111`.
   - Done: post-`0010` struct regression probe shows `Point p{2,5}` still
     rendering as a `Point` `C_STRUCT` with `x` and `y`, with `p.y` progressing
     to `7` and stderr clean.
   - Done: post-`0012` `std::vector<int>` probe compiles/runs with stdout `28`
     and clean Valgrind/postprocess stderr. `nums` now renders as
     `std::vector<int>`; after initialization it reports `size = 3`,
     `capacity = 3`, and an `elements` array. After `push_back(4)` and
     `nums[1] = 20`, it reports `size = 4`, `capacity = 6`, and active element
     values `1,20,3,4`.
   - Done: post-`0012` `std::string` mutation regression still renders clean
     `std::string` values, keeps postprocess stderr empty, and reaches stdout
     `cats Hippopotamus` with Valgrind reporting zero errors.
   - Done: post-`0006` `std::vector<Point>` probe compiles/runs with stdout
     `46` and clean Valgrind/postprocess stderr. `pts` renders as
     `std::vector<Point>` with active `Point` elements. After `push_back({5, 6})`
     and `pts[1].y = 40`, it reports `size = 3`, `capacity = 4`, and active
     structured elements `{1,2}`, `{3,40}`, and `{5,6}`.
   - Done: post-`0006` regressions keep `std::vector<int>` element rendering
     working with values `1,20,3,4`, and keep `std::string` mutation rendering
     working with stdout `cats Hippopotamus`.
   - Done: post-`0007` `std::vector<std::string>` probe compiles/runs with
     stdout `alpha beta! gamma` and clean Valgrind/postprocess stderr. `words`
     renders as `std::vector<std::string>` with active `std::string` elements,
     not the raw libstdc++ `std::__cxx11::basic_string<...>` spelling.
   - Done: post-`0007` `std::vector<int>` regression still renders active
     element values including the mutated `20`, with stdout `28`.
   - Done: post-`0008` `std::array<int, 3>` and `std::array<Point, 2>` probe
     compiles/runs with stdout `32` and clean Valgrind/postprocess stderr.
     `nums` renders as `std::array<int, 3>` with `size = 3` and elements
     `1,20,3`; `pts` renders as `std::array<Point, 2>` with `size = 2` and
     structured `Point` elements, including `pts[1].y` progressing to `8`.
   - Done: post-`0008` `std::vector<std::string>` regression still renders
     clean `std::vector<std::string>` summaries with active elements and stdout
     `alpha beta! gamma`.
   - Done: post-`0009` `std::pair<int, std::string>` probe compiles/runs with
     stdout `10 cat dogs` and clean Valgrind/postprocess stderr. `item` renders
     as `std::pair<int, std::string>` with `first` progressing to `10` and
     `second` rendered as `std::string`.
   - Done: post-`0009` `std::array<int, 3>` / `std::array<Point, 2>` regression
     still renders clean `std::array` summaries with active elements and stdout
     `32`.
   - Done: post-`0010` `std::unique_ptr<int>`, `std::unique_ptr<Point>`, and
     `std::unique_ptr<std::string>` probe compiles/runs with stdout
     `10 15 cats` and clean Valgrind/postprocess stderr. The trace shows
     `std::unique_ptr<int>` with `pointee = 10`, `std::unique_ptr<Point>` with
     `pointee = Point{x = 2, y = 15}`, and `std::unique_ptr<std::string>` with
     the owned string object represented through the existing pointer-style
     `std::string` value.
   - Done: post-`0010` `std::pair<int, std::string>` regression still renders
     clean `std::pair<int, std::string>` summaries and produces stdout
     `10 cat dogs` with clean Valgrind/postprocess stderr.
   - Done: post-`0011` `std::tuple<int, double, std::string>` and
     `std::tuple<int, Point>` probe compiles/runs with stdout `10 dogs 12`
     and clean Valgrind/postprocess stderr. `a` renders as
     `std::tuple<int, double, std::string>` with `size = 3` and elements
     `0 = 10`, `1 = 2.5`, and `2 = std::string`; `b` renders as
     `std::tuple<int, Point>` with `size = 2`, `0 = 7`, and structured
     `Point{x = 2, y = 12}`.
   - Done: post-`0011` `std::pair<int, std::string>` / tuple regression
     renders clean summaries for both `std::pair<int, std::string>` and
     `std::tuple<int, double, std::string>` with stdout `10 cat dogs`.
   - Done: post-`0011` `std::unique_ptr<int>`, `std::unique_ptr<Point>`, and
     `std::unique_ptr<std::string>` regression still renders smart-pointer
     summaries with pointee-bearing steps and stdout `10 15 cats`.
   - Done: post-`0012` `std::shared_ptr<int>` and `std::shared_ptr<Point>`
     probe compiles/runs with stdout `10 15 2` and clean
     Valgrind/postprocess stderr. `a` and `copy` render as
     `std::shared_ptr<int>` with `use_count = 2` and pointee progressing from
     `7` to `10`; `p` renders as `std::shared_ptr<Point>` with
     `use_count = 1` and structured pointee `Point{x = 2, y = 15}`.
   - Done: post-`0012` smoke, tuple/pair regression, and `unique_ptr`
     regression still pass with clean Valgrind/postprocess stderr.
   - Done: post-control-character-escape `std::shared_ptr<std::string>` probe
     compiles/runs with stdout `10 15 cats 2`, clean Valgrind/postprocess
     stderr, parseable trace JSON, and escaped character heap bytes such as
     `\u0002` instead of raw control characters.
   - Done: post-`0013` `std::shared_ptr<std::string>` probe now renders `s`
     with `pointer`, `use_count = 1`, and `pointee = std::string` instead of
     the previous unsupported struct placeholder; scalar and simple
     struct/class shared-pointer regressions still pass in the same probe.
   - Done: post-Valgrind-`0013` `std::optional<int>`,
     `std::optional<Point>`, `std::optional<std::string>`, and
     `std::variant<int, std::string>` probe compiles/runs with stdout
     `10 15 cats dogs`, clean postprocess stderr, and Valgrind reporting zero
     errors. The raw trace now exposes optional `_M_value` payloads and variant
     `_M_u` alternatives instead of empty union shells.
   - Done: post-`0014`/`0015` optional/variant probe still compiles/runs with
     stdout `10 15 cats dogs`, clean postprocess stderr, and Valgrind
     reporting zero errors. `oi` renders as `std::optional<int>` with
     `value = 10`, `op` renders as `std::optional<Point>` with
     `Point{x = 2, y = 15}`, and `os` renders as `std::optional<std::string>`
     with a pointer-style string value backed by the heap character buffer.
     `v` renders as `std::variant<int, std::string>` with `index`,
     `active_type`, and only the selected alternative; the `int` alternative
     renders cleanly as `3`, while the active `std::string` alternative still
     exposes raw aligned in-place storage bytes for `dogs`.
   - Done: post-`0016`/`0017`/`0018` optional/variant probe still compiles/runs
     with stdout `10 15 cats dogs`, clean postprocess stderr, parseable JSON,
     and Valgrind reporting zero errors. The active `std::string` alternative
     in `v` now renders as a pointer-style `std::string` value backed by a heap
     character array containing `d,o,g,s,\0` instead of raw aligned in-place
     storage bytes.
   - Done: post-`0019` `std::weak_ptr<int>` and `std::weak_ptr<Point>` probe
     compiles/runs with stdout `10 15 2`, clean postprocess stderr, parseable
     JSON, and Valgrind reporting zero errors. `wi` renders as
     `std::weak_ptr<int>` with `pointer`, live `use_count`, and pointee
     progressing from `7` to `10`; `wp` renders as `std::weak_ptr<Point>` with
     `pointer`, `use_count = 1`, and structured pointee
     `Point{x = 2, y = 15}` after mutation.
   - Done: post-`0020` stack-backed `std::span<int>` and `std::span<Point>`
     probe compiles/runs with stdout `20 3 14`, clean postprocess stderr,
     parseable JSON, and Valgrind reporting zero errors. `all`, `mid`, and
     `points` render as source-level `std::span<T>` summaries with `data` and
     `size`, while the backing stack arrays show the element mutations.
   - Done: post-`0020` vector-backed `std::span<int>` probe with reserved
     capacity compiles/runs with stdout `30 2 5`, clean postprocess stderr,
     parseable JSON, and Valgrind reporting zero errors. `view` renders active
     heap-backed elements `1,2,30,4`; `tail` renders the sliced elements
     `30,4`; after `push_back(5)`, `nums` grows to five elements while `view`
     remains a four-element span.
   - Done: post-`0021` `std::string` / `std::string_view` probe compiles/runs
     with stdout `hello World|World`, clean postprocess stderr, parseable JSON,
     and Valgrind reporting zero errors. `all` renders as `std::string_view`
     with `size = 11` and characters `hello World`; `word` renders as a
     five-character substring view whose characters update from `world` to
     `World` after the backing string mutation.
   - Done: post-`0022` `std::chrono::milliseconds`,
     `std::chrono::seconds`, and `std::chrono::time_point` probe compiles/runs
     with stdout `1750 1 1775`, clean postprocess stderr, parseable JSON, and
     Valgrind reporting zero errors. `ms` renders as
     `std::chrono::milliseconds` with `count = 1750`, `sec` renders as
     `std::chrono::seconds` with `count = 1`, and `tp` renders as
     `std::chrono::time_point<std::chrono::steady_clock,
     std::chrono::milliseconds>` with nested `time_since_epoch.count = 1775`.
   - Done: post-`0023` `std::bitset<8>` probe compiles/runs with stdout
     `136 2`, clean postprocess stderr, parseable JSON, and Valgrind reporting
     zero errors. `bits` renders as `std::bitset<8>` with `size = 8`,
     `value = 136`, and bit entries showing bits 3 and 7 set after the final
     mutation.
   - Done: post-`0024` `std::atomic<int>` probe compiles/runs with stdout
     `7 1`, clean postprocess stderr, parseable JSON, and Valgrind reporting
     zero errors. `counter` renders as `std::atomic<int>` with `value`
     progressing from `<UNINITIALIZED>` to `3` and then `7`.
   - Done: post-`0025` `std::initializer_list<int>` probe compiles/runs with
     stdout `3 6`, clean postprocess stderr, parseable JSON, and Valgrind
     reporting zero errors. `nums` renders as `std::initializer_list<int>`
     with `data` and `size = 3` in both the caller and callee frames.
5. Run modern C++ wrapper tests and compare trace shape against the stable
   `cpp-tutor/opt-cpp-backend-cpp20-sb:local` image.
6. Only after those pass, use `start-all-valgrind327-experimental.sh` for
   browser testing.
