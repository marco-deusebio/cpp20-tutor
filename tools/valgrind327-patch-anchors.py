#!/usr/bin/env python3
from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parents[1]
OLD = ROOT / "v4-cokapi/backends/c_cpp/valgrind-3.11.0"
NEW = ROOT / "local-cpp20-backend/valgrind-3.27.1-src"


CHECKS = {
    "memcheck/mc_include.h": [
        "pg_source_filename",
        "VG_(pg_traverse_global_var)",
        "VG_(pg_traverse_local_var)",
        "MC_(clo_keep_stacktraces)",
    ],
    "memcheck/mc_main.c": [
        "LeakCheckMode MC_(clo_leak_check)",
        "pg_source_filename_init",
        "trace_fp",
        "stdout_fd",
        "--source-filename",
        "--trace-filename",
        "static void mc_post_clo_init",
        "VG_(dup2)(stdout_fd, 1)",
        "VG_(fclose)(trace_fp)",
    ],
    "memcheck/mc_translate.c": [
        "pub_tool_libcfile.h",
        "pub_tool_debuginfo.h",
        "pub_tool_stacktrace.h",
        "pub_tool_threadstate.h",
        "pub_tool_oset.h",
        "pg_trace_inst",
        "MAX_STEPS",
        "pg_encoded_addrs",
        "VG_(get_filename)",
        "VG_(get_and_pp_StackTrace)",
        "VG_(pg_traverse_global_var)",
        "VG_(pg_traverse_local_var)",
        "unsafeIRDirty",
        "Ist_IMark",
    ],
    "include/pub_tool_debuginfo.h": [
        "VG_(pg_traverse_global_var)",
        "VG_(pg_traverse_local_var)",
        "StackBlock",
        "GlobalBlock",
        "VG_(di_get_global_blocks_from_dihandle)",
    ],
    "coregrind/m_debuginfo/debuginfo.c": [
        "VG_(pg_traverse_global_var)",
        "VG_(pg_traverse_local_var)",
        "StackBlock block",
        "GlobalBlock gb",
        "VG_(di_get_global_blocks_from_dihandle)",
        "ML_(describe_type)",
        "data_address_is_in_var",
    ],
}


def find_lines(path, needles):
    if not path.exists():
        return {needle: [] for needle in needles}

    hits = {needle: [] for needle in needles}
    for lineno, line in enumerate(path.read_text(errors="replace").splitlines(), 1):
        for needle in needles:
            if needle in line:
                hits[needle].append((lineno, line.rstrip()))
    return hits


def print_section(title, base):
    print(f"# {title}")
    for rel, needles in CHECKS.items():
        path = base / rel
        print(f"\n## {rel}")
        for needle, hits in find_lines(path, needles).items():
            if hits:
                joined = "; ".join(f"{lineno}: {text.strip()}" for lineno, text in hits[:6])
                extra = "" if len(hits) <= 6 else f" (+{len(hits) - 6} more)"
                print(f"- `{needle}`: {joined}{extra}")
            else:
                print(f"- `{needle}`: missing")


def main():
    old = Path(sys.argv[1]) if len(sys.argv) > 1 else OLD
    new = Path(sys.argv[2]) if len(sys.argv) > 2 else NEW

    print_section(f"Old Patched Source: {old}", old)
    print()
    print_section(f"New Experimental Source: {new}", new)


if __name__ == "__main__":
    main()
