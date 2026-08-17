#!/usr/bin/env python3
"""Compare stable (Valgrind 3.11) and experimental (Valgrind 3.27) traces.

Answers two questions the porting checklist cares about:
  1. Does each backend produce a usable trace at all, or does it crash?
  2. Where both work, which source-level types does each actually render?

Rendered type names are the comparison unit rather than raw JSON: the two
backends legitimately differ in addresses and step counts, but the type a
local displays as is the thing a student sees.
"""
import json
import re
import sys
from pathlib import Path

# libstdc++ internals visible in a rendering mean the summary fell back to raw
LEAK_MARKERS = ("_M_dataplus", "_M_elems", "_M_head_impl", "_Rb_tree",
                "_M_start", "_M_refcount", "__cxx11", "_M_value")


def load(path):
    """Return (status, trace). status is 'ok' or a short failure reason."""
    if not path.exists():
        return "no-output", []
    raw = path.read_text(errors="replace")
    if not raw.strip():
        return "empty", []
    try:
        data = json.loads(raw)
    except ValueError:
        return "bad-json", []
    trace = data.get("trace") or []
    if not trace:
        return "zero-steps", []
    for step in trace:
        if step.get("event") == "uncaught_exception":
            return "compile/run-fail", trace
    return "ok", trace


def crash_reason(err_path):
    if not err_path.exists():
        return ""
    err = err_path.read_text(errors="replace")
    match = re.search(r"valgrind: .*Assertion '([^']+)' failed", err)
    if match:
        return "valgrind assertion: %s" % match.group(1)
    if "Ugh, bad record" in err:
        return "postprocessor rejected a record"
    return ""


def rendered_types(trace):
    """Map local name -> the set of type names it rendered as."""
    types = {}
    for step in trace:
        for frame in step.get("stack_to_render") or []:
            for name, value in (frame.get("encoded_locals") or {}).items():
                if not isinstance(value, list) or len(value) < 3:
                    continue
                types.setdefault(name, set()).add(str(value[2]))
    return types


def leaks(trace):
    blob = json.dumps(trace)
    return sorted({m for m in LEAK_MARKERS if m in blob})


def main():
    probe_dir, out_dir = Path(sys.argv[1]), Path(sys.argv[2])
    rows = []
    detail = []

    for src in sorted(probe_dir.glob("*.cpp")):
        name = src.stem
        s_status, s_trace = load(out_dir / ("%s.stable.out" % name))
        e_status, e_trace = load(out_dir / ("%s.experimental.out" % name))
        if s_status == "no-output" and e_status == "no-output":
            continue

        s_note = s_status
        if s_status != "ok":
            reason = crash_reason(out_dir / ("%s.stable.err" % name))
            if reason:
                s_note = "%s (%s)" % (s_status, reason)

        rows.append((name, len(s_trace), s_note, len(e_trace), e_status))

        if s_status == "ok" and e_status == "ok":
            s_types, e_types = rendered_types(s_trace), rendered_types(e_trace)
            diffs = []
            for local in sorted(set(s_types) | set(e_types)):
                s_set = s_types.get(local, set())
                e_set = e_types.get(local, set())
                if s_set != e_set:
                    diffs.append("    %-12s stable=%s  experimental=%s"
                                 % (local,
                                    ",".join(sorted(s_set)) or "-",
                                    ",".join(sorted(e_set)) or "-"))
            if diffs:
                detail.append("  %s" % name)
                detail.extend(diffs)

    if not rows:
        print("no comparison output found; run compare-backends.sh first")
        return 1

    width = max(len(r[0]) for r in rows) + 1
    print("%-*s %7s  %-42s %7s  %s"
          % (width, "probe", "stable", "stable status", "exp", "experimental status"))
    for name, s_steps, s_note, e_steps, e_status in rows:
        print("%-*s %7d  %-42s %7d  %s"
              % (width, name, s_steps, s_note[:42], e_steps, e_status))

    stable_ok = sum(1 for r in rows if r[2] == "ok")
    exp_ok = sum(1 for r in rows if r[4] == "ok")
    print("\nusable traces: stable %d/%d, experimental %d/%d"
          % (stable_ok, len(rows), exp_ok, len(rows)))

    if detail:
        print("\ndiffering rendered types (both backends usable):")
        print("\n".join(detail))
    return 0


if __name__ == "__main__":
    sys.exit(main())
