# Local runbook

## Start
Build the local C++20 backend image once:

./build-cpp20-backend.sh

Run:

./start-all.sh

Then open:
http://localhost:5000/visualize.html

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

This image is intentionally separate from the stable local backend. It keeps
the current wrapper layer but points `run_cpp_backend.py` at Valgrind 3.27.1.
The current experimental patch stack restores cpp-tutor trace emission and
basic step-by-step stack/line visualization, but local/global variable value
serialization is still being forward-ported. See `VALGRIND327-EXPERIMENT.md`
for the current status and patch-porting checklist.

## Stop
Press Ctrl+C in the terminal running ./start-all.sh
