#!/usr/bin/env python3
"""Reduces an xctrace os_signpost recording to AeroSpace's session and AX numbers.

Usage: reduce-trace.py <trace> [--from S] [--to S] [--process NAME]

Exports the OSSignpostIntervals table (Instruments pairs begin and end itself), keeps intervals
whose subsystem starts with bobko.aerospace, and prints:
- light and complete refresh sessions: count, rate per second, median and max duration;
- AX intervals (get, set, containingWindowId) per app thread: count, total, median, max, and the
  attribute when the build logs it publicly (release builds redact it as <private>).

--long MS lists every interval over MS by start time instead.
--from/--to keep intervals that start inside that window, in seconds from the recording's start.
Brief 01, 2026-11-01.
"""
import argparse, collections, statistics, subprocess, sys, os
import xml.etree.ElementTree as ET

ap = argparse.ArgumentParser()
ap.add_argument("trace")
ap.add_argument("--from", dest="t_from", type=float, default=0.0)
ap.add_argument("--to", dest="t_to", type=float, default=1e9)
ap.add_argument("--process", default=None, help="substring of the process name, e.g. AeroSpaceApp")
ap.add_argument("--long", type=float, default=None, help="instead, list intervals longer than this many ms, by start time")
args = ap.parse_args()

xpath = '/trace-toc/run[@number="1"]/data/table[@schema="OSSignpostIntervals"]'
out = args.trace.rstrip("/") + ".intervals.xml"  # cached next to the trace
if not os.path.exists(out):
    subprocess.run(["xcrun", "xctrace", "export", "--input", args.trace, "--xpath", xpath, "--output", out],
                   check=True, stdout=subprocess.DEVNULL)

# Columns, in order: start, duration, layout-id, name, category, subsystem, identifier, process,
# end-process, start-thread, end-thread, start-message, end-message, ...
interned = {}  # id -> (text, fmt)


def resolve(el):
    ref = el.get("ref")
    if ref is not None:
        return interned.get(ref, ("", ""))
    val = (el.text or "", el.get("fmt", el.text or ""))
    if el.get("id") is not None:
        interned[el.get("id")] = val
    return val


rows = []
for ev, el in ET.iterparse(out, events=("end",)):
    if el.tag != "row":
        continue
    cells = list(el)
    # Children are interned when first seen, possibly nested (process inside thread); intern all.
    for c in el.iter():
        if c is not el and c.get("id") is not None and c.get("id") not in interned:
            interned[c.get("id")] = (c.text or "", c.get("fmt", c.text or ""))
    vals = [resolve(c) for c in cells]
    if len(vals) < 12:
        el.clear(); continue
    subsystem = vals[5][1]
    if not subsystem.startswith("bobko.aerospace"):
        el.clear(); continue
    start_s = int(vals[0][0]) / 1e9
    dur_ms = int(vals[1][0]) / 1e6
    rows.append(dict(start=start_s, dur=dur_ms, name=vals[3][1], process=vals[7][1],
                     thread=vals[9][1], msg=vals[11][1]))
    el.clear()

rows = [r for r in rows if args.t_from <= r["start"] < args.t_to]
if args.process:
    rows = [r for r in rows if args.process in r["process"]]
if not rows:
    sys.exit(f"no AeroSpace intervals in {args.t_from}-{args.t_to} s")
if args.long is not None:
    for r in sorted(rows, key=lambda r: r["start"]):
        if r["dur"] >= args.long:
            thread = r["thread"].split(" (0x")[0].replace("AxAppThread ", "")
            print(f"{r['start']:8.3f}  {r['dur']:8.1f} ms  {r['name'][:32]:32s} {thread[:50]:50s} {r['msg'][:40]}")
    sys.exit(0)
span = ((args.t_to if args.t_to < 1e9 else max(r["start"] for r in rows)) - max(args.t_from, 0.0)) or 1.0  # pass --to for exact rates


def stats(ds):
    return f"n {len(ds):4d}  total {sum(ds):8.1f}  median {statistics.median(ds):7.2f}  max {max(ds):8.1f} ms"


print(f"processes: {sorted({r['process'] for r in rows})}  window {args.t_from:.0f}-{min(args.t_to, args.t_from + span):.0f} s")
for name, label in [("runLightSession", "light sessions"), ("runHeavyCompleteRefreshSession", "complete refreshes")]:
    ds = [r["dur"] for r in rows if r["name"].startswith(name)]
    if ds:
        print(f"{label:20s} {stats(ds)}  rate {len(ds) / span:.2f}/s")
    else:
        print(f"{label:20s} none")

ax = collections.defaultdict(list)
for r in rows:
    if r["name"].startswith(("get(", "set(", "containingWindowId")):
        thread = r["thread"].split(" (0x")[0].replace("AxAppThread ", "")
        attr = r["msg"].split(" axTaskLocalAppThreadToken")[0].replace("attr: ", "")
        ax[(thread, r["name"].split("(")[0], attr)].append(r["dur"])
print("AX intervals by app thread, call, attribute (sorted by total time):")
for key, ds in sorted(ax.items(), key=lambda kv: -sum(kv[1]))[:25]:
    print(f"  {key[0][:55]:55s} {key[1]:18s} {key[2][:28]:28s} {stats(ds)}")
