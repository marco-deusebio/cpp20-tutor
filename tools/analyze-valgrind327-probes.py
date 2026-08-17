#!/usr/bin/env python3
"""Classify probe output from probe-valgrind327-edge-cases.sh.

Flags the failure modes this backend has actually produced: records the
postprocessor rejected (which silently drops every later step), traces that
came back empty or truncated, and summaries that bailed out and exposed raw
libstdc++ implementation members.
"""
import json
import re
import sys
from pathlib import Path

# libstdc++ member names a working summary should have hidden. Matched in
# their quoted JSON-key form: a bare substring test would make "_M_i" fire on
# _M_impl and "_M_w" fire on _M_weak_count.
LEAK_MEMBER_NAMES = [
    "_M_dataplus", "_M_start", "_M_finish", "_M_elems", "_M_i", "_M_value",
    "_M_ptr", "_M_refcount", "_M_u", "_M_index", "_M_first", "_M_rest",
    "_M_head_impl", "_M_t", "_M_pi", "_M_engaged", "_M_payload", "_M_extent",
    "_M_str", "_M_len", "_M_string_length", "_M_local_buf", "_M_w",
]

# not member names, so matched as plain substrings
LEAK_MARKERS = ["__cxx11", "_Coro_", "_Rb_tree", "f32:", "f64:"]

LEAK_PATTERNS = ['"%s"' % n for n in LEAK_MEMBER_NAMES] + LEAK_MARKERS

# probes that are expected to report Valgrind errors by construction
EXPECT_VALGRIND_ERRORS = {"uninit_reads"}


def main():
    probe_dir, out_dir = Path(sys.argv[1]), Path(sys.argv[2])
    rows = []

    for src in sorted(probe_dir.glob("*.cpp")):
        name = src.stem
        out_path, err_path = out_dir / (name + ".out"), out_dir / (name + ".err")
        if not out_path.exists():
            continue
        src_lines = len([l for l in src.read_text().splitlines() if l.strip()])
        notes = []

        err = err_path.read_text(errors="replace") if err_path.exists() else ""
        raw = out_path.read_text(errors="replace")

        if "Ugh, bad record" in err:
            notes.append("POSTPROC-REJECT")
        match = re.search(r"ERROR SUMMARY: (\d+) errors", err)
        if not match:
            notes.append("NO-ERROR-SUMMARY")
        elif match.group(1) != "0" and name not in EXPECT_VALGRIND_ERRORS:
            notes.append("VALGRIND-ERRORS(%s)" % match.group(1))

        if not raw.strip():
            rows.append((name, "-", src_lines, "EMPTY-OUTPUT"))
            continue
        try:
            data = json.loads(raw)
        except ValueError as exc:
            rows.append((name, "-", src_lines, "BAD-JSON: %s" % str(exc)[:40]))
            continue

        trace = data.get("trace") or []
        steps = len(trace)
        if steps == 0:
            notes.append("ZERO-STEPS")
        for step in trace:
            if step.get("event") == "uncaught_exception":
                notes.append("COMPILE/RUN-FAIL: %s"
                             % (step.get("exception_msg") or "")[:60])
                break

        blob = json.dumps(trace)
        leaked = sorted({p for p in LEAK_PATTERNS if p in blob})
        if leaked:
            notes.append("LEAKED-INTERNALS: " + ",".join(leaked))

        # a trace far shorter than its source suggests dropped steps
        if 0 < steps < max(2, src_lines // 4):
            notes.append("SHORT-TRACE(%d steps / %d lines)" % (steps, src_lines))

        rows.append((name, steps, src_lines, "; ".join(notes) if notes else "ok"))

    if not rows:
        print("no probe output found; run probe-valgrind327-edge-cases.sh first")
        return 1

    width = max(len(r[0]) for r in rows) + 1
    print("%-*s %6s %6s  %s" % (width + 1, " probe", "steps", "lines", "notes"))
    for name, steps, lines, note in rows:
        print("%s%-*s %6s %6s  %s"
              % (" " if note == "ok" else "!", width, name, steps, lines, note))

    bad = [r for r in rows if r[3] != "ok"]
    print("\n%d/%d probes flagged" % (len(bad), len(rows)))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
