#!/bin/bash
# Records a signpost trace: <idle> seconds untouched, then the 1<->2 switch series, then reduces it.
# Usage: run-scenario.sh <name> <aerospace-cli> <server-process-name> [idle=20] [A=1] [B=2] [N=20]
# Traces go to $OUT (default: the session scratchpad). Brief 01, 2026-11-01.
set -u
name=$1 cli=$2 proc=$3 idle=${4:-20} a=${5:-1} b=${6:-2} n=${7:-20}
pid=$(pgrep -x "$proc" | head -1)
[ -n "$pid" ] || { echo "no process $proc"; exit 1; }
out=${OUT:?set OUT to a directory for traces}
extra=()
[ -n "${PROFILE:-}" ] && extra=(--instrument "Time Profiler" --instrument Hangs)
here=$(cd "$(dirname "$0")" && pwd)
rm -rf "$out/$name.trace"
xcrun xctrace record --instrument os_signpost "${extra[@]}" --all-processes --time-limit $((idle + n + 25))s \
    --output "$out/$name.trace" >"$out/$name.record.log" 2>&1 &
rec=$!
sleep "$idle"
echo "== $name: switch series ($cli)"
python3 "$here/switch-series.py" "$cli" "$a" "$b" "$n" 0.4
wait $rec
[ -n "${SKIP_REDUCE:-}" ] && exit 0
echo "== $name: idle window 2-$idle s"
python3 "$here/reduce-trace.py" "$out/$name.trace" --from 2 --to "$idle" | head -12
echo "== $name: series window"
python3 "$here/reduce-trace.py" "$out/$name.trace" --from "$idle" | head -20
