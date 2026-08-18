# Local runbook

## Start
Build the local C++20 backend image once:

./build-cpp20-backend.sh

Run:

./start-all.sh

Then open:
http://localhost:5050/visualize.html

The local C++ backend compiles with GNU++20 and includes compatibility rewrites
for common modern features such as structured bindings, `std::numbers`,
`std::ssize`, string `starts_with` / `ends_with` / `contains`, selected
`std::ranges` algorithms, container `contains`, `std::cmp_*`,
`std::to_underlying`, `std::midpoint`, simple `std::views::iota` loops,
simple `std::views::reverse` loops, simple braced `std::views::filter` and
`std::views::transform` loops, common `std::ranges::remove/remove_if` erase
idioms, `std::reduce`,
`std::lerp`, `std::clamp`, `std::gcd`, `std::lcm`, selected `<bit>` helpers,
`std::erase`, and `std::erase_if`.
Generated compatibility code is hidden from returned traces so source
highlighting stays aligned with the original program where possible.

## Experimental Valgrind 3.27 Backend
There is a parallel Valgrind 3.27.1 image build for patch-porting work:

./build-valgrind327-backend.sh

Run it with:

./start-all-valgrind327-experimental.sh

Or, after installing the local command shim:

cpp20-tutor

This image is intentionally separate from the stable local backend. It keeps
the current wrapper layer, points `run_cpp_backend.py` at Valgrind 3.27.1, and
uses GCC 11.4 for native C++20 user programs. The experimental patch stack
restores cpp-tutor trace emission, local/global values, source-level summaries
for many standard-library types, three-way comparison categories, native range
iteration, C++20 threading, and cleaned coroutine call/return visualization. See
`VALGRIND327-EXPERIMENT.md`
for the verified feature list, remaining representation limits, and
patch-porting checklist.

## Rebuilding the frontend

The visualizer bundles in `v5-unity/build/` are generated from
`v5-unity/js/*.ts` by webpack:

    cd v5-unity && node_modules/.bin/webpack

Do not hand-edit a bundle. The C++ language label was previously changed
directly in `visualize.bundle.js` without the matching change in
`pytutor.ts`, so any rebuild silently reverted it to `C++ (gcc 4.8, C++11)`
and the other eight bundles still carried the stale label. The label now
lives in `pytutor.ts` and two consecutive builds produce byte-identical
bundles, so a rebuild is safe.

## Stop
Press Ctrl+C in the terminal running ./start-all.sh
