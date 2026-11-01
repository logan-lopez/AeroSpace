#!/usr/bin/env python3
"""Times N alternating `aerospace workspace A` / `workspace B` calls; prints median and max in ms.

Usage: switch-series.py <aerospace-cli> <A> <B> [N=20] [pause-seconds=0.4] [--load] [--timeout S]

The CLI reply waits for the light session (Sources/AppBundle/server.swift), so this is what a
hotkey feels like, minus the follow-up complete refresh.

--load adds a sketchybar-like load on the same server: after each switch, the three queries
Logan's sketchybar sends on a workspace or focus change (list-workspaces --all, list-windows
--all, list-windows --focused), fired without waiting, plus one list-windows --focused per
second. Use it against the debug server, which sketchybar doesn't talk to.

--warmup K runs K switches first that aren't counted (a fresh debug server settles over the
first few).

--timeout aborts the series when one switch takes longer than S seconds (default 20), so a
wedged server doesn't hang the run. Brief 01, 2026-11-01.
"""
import statistics, subprocess, sys, time

import argparse
ap = argparse.ArgumentParser()
ap.add_argument("cli"); ap.add_argument("a"); ap.add_argument("b")
ap.add_argument("n", nargs="?", type=int, default=20)
ap.add_argument("pause", nargs="?", type=float, default=0.4)
ap.add_argument("--load", action="store_true")
ap.add_argument("--timeout", type=float, default=20.0)
ap.add_argument("--warmup", type=int, default=0, help="extra switches first, not counted")
opts = ap.parse_args()
cli, a, b, n, pause, load, timeout = opts.cli, opts.a, opts.b, opts.n, opts.pause, opts.load, opts.timeout

QUIET = dict(stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
LOAD_QUERIES = [
    ["list-workspaces", "--all", "--json", "--format", "%{workspace} %{workspace-is-focused} %{workspace-is-visible}"],
    ["list-windows", "--all", "--json", "--format", "%{workspace} %{app-name} %{app-bundle-id}"],
    ["list-windows", "--focused", "--json", "--format", "%{app-name} %{window-title} %{app-bundle-id}"],
]
background = []
last_poll = time.monotonic()


def fire(query):
    background.append(subprocess.Popen([cli, *query], **QUIET))


samples = []
aborted = False
warmup = opts.warmup
for i in range(n + warmup):
    ws = b if i % 2 else a
    t0 = time.perf_counter()
    try:
        subprocess.run([cli, "workspace", ws], check=False, timeout=timeout, **QUIET)
    except subprocess.TimeoutExpired:
        samples.append(timeout * 1000)  # counted even during warmup: a wedge is the result
        aborted = True
        break
    if i >= warmup:
        samples.append((time.perf_counter() - t0) * 1000)
    if load:
        for q in LOAD_QUERIES:
            fire(q)
    deadline = time.monotonic() + pause
    while time.monotonic() < deadline:
        if load and time.monotonic() - last_poll >= 1.0:
            fire(LOAD_QUERIES[2])
            last_poll = time.monotonic()
        time.sleep(0.05)
pending = sum(1 for p in background if p.poll() is None)
for p in background:
    if p.poll() is None:
        p.kill()
note = f"  ABORTED: a switch took over {timeout:.0f} s" if aborted else ""
loadnote = f"  load: {len(background)} queries, {pending} still pending at the end" if load else ""
print(f"n {len(samples)}  median {statistics.median(samples):.1f} ms  max {max(samples):.1f} ms  min {min(samples):.1f} ms{note}{loadnote}")
print("raw:", " ".join(f"{s:.0f}" for s in samples))
