#!/bin/bash
# Runs the switch series against a fork debug build: starts its AeroSpaceApp (which switches the
# installed AeroSpace off), waits for it to answer, runs switch-series.py with --load, then stops
# it with SIGINT (which switches the installed AeroSpace back on).
# PLACE=<bundle-id>:<workspace> places an app's windows first (see below).
# TRACE=<path.trace> also records an os_signpost trace attached to the server.
# Usage: fork-series.sh <dir with aerospace and AeroSpaceApp> <label> [A=1] [B=2] [N=20]
# Brief 01, 2026-11-01.
set -u
dir=$1 label=$2 a=${3:-1} b=${4:-2} n=${5:-20}
here=$(cd "$(dirname "$0")" && pwd)
log=${TMPDIR:-/tmp}/fork-series-$label.log
"$dir/AeroSpaceApp" >"$log" 2>&1 &
server=$!
trap 'kill -INT $server 2>/dev/null; wait $server 2>/dev/null' EXIT
for _ in $(seq 1 60); do
    "$dir/aerospace" list-workspaces --focused >/dev/null 2>&1 && break
    sleep 0.5
done
sleep 3 # let the startup refresh settle
# PLACE="<bundle-id>:<workspace>" moves that app's windows there first: a fresh debug server
# assigns windows to the visible workspace of the monitor they're on, not where the installed
# AeroSpace had them.
if [ -n "${PLACE:-}" ]; then
    bundle=${PLACE%%:*} ws=${PLACE##*:}
    ids=
    for _ in $(seq 1 60); do # the startup refresh can take a while to register a slow app's windows
        ids=$("$dir/aerospace" list-windows --all --format '%{window-id} %{app-bundle-id}' | awk -v b="$bundle" '$2 == b {print $1}')
        [ -n "$ids" ] && break
        sleep 1
    done
    [ -n "$ids" ] || { echo "no $bundle window registered; not running"; exit 1; }
    for id in $ids; do
        "$dir/aerospace" move-node-to-workspace --window-id "$id" "$ws"
    done
    placed=$("$dir/aerospace" list-windows --all --format '%{workspace} %{window-layout} %{app-bundle-id}' | awk -v b="$bundle" '$3 == b')
    echo "placed: $placed"
    echo "$placed" | awk -v w="$ws" '$1 != w {bad = 1} END {exit bad}' || { echo "placement failed; not running"; exit 1; }
    sleep 3
fi
echo "== $label"
if [ -n "${TRACE:-}" ]; then
    rm -rf "$TRACE"
    xcrun xctrace record --instrument os_signpost --attach "$server" --time-limit "$((n * 2 + 30))s" --output "$TRACE" >"$log.xctrace" 2>&1 &
    rec=$!
    sleep 2
fi
python3 "$here/switch-series.py" "$dir/aerospace" "$a" "$b" "$n" 0.4 --load --timeout 20 --warmup 6
if [ -n "${TRACE:-}" ]; then kill -INT $rec 2>/dev/null; wait $rec; fi
