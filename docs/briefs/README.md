# Briefs

Each brief is a self-contained handoff for a fresh session. New ones go here, numbered in order,
and move to `archive/` when they're done. Ideas that aren't scheduled yet are in
[`FUTURE.md`](FUTURE.md).

## Where things stand

*Updated 2026-11-01.*

- The fork's `main` is upstream's `main` (nikitabobko/AeroSpace) at `7c0f987c` (2026-11-01), plus
  these docs. It has no code changes of its own yet.
- The main reason for the fork is a performance issue: with Godot or a Moonlight stream running,
  workspace switches and commands lag for seconds. It may go upstream (it overlaps upstream
  #1615).
- Next: [brief 01](01-godot-moonlight-lag-spike.md), a spike that measures it and lands a local
  fix or stops at a no-go. Before it can build, Logan installs bash 5 and swiftly
  ([running the fork](../guide/running-the-fork.md)), and the run needs him at the desktop to
  start a Moonlight stream.
- Loose end: writing the architecture pages turned up three likely upstream bugs, not yet
  reproduced. In `Sources/AppBundle/windowLevelCache.swift`, the latch is cleared before it's
  signalled, so waiters hang. `Int32ExitCode.succ` is 2. Quit can block forever on a window the
  app thread already pruned.
- The fork's docs live only in new paths, so merging upstream doesn't conflict. Upstream PRs branch
  from `upstream/main`, a remote added on 2026-11-01
  ([decisions](../decisions/README.md)).
- Also open (2026-11-02): [brief 02](02-window-is-focused-format-variable.md), a small format
  variable for Wicket, independent of 01. Installing it means a build that merges it with
  `slow-app-lag`.

## Open

In the order they should be done. A status tag follows the link when it isn't "not started".

1. [`01-godot-moonlight-lag-spike.md`](01-godot-moonlight-lag-spike.md) (done, awaiting review): spike on the lag Godot
   and Moonlight windows cause across all of AeroSpace. Measure, name the stall, land a local fix
   upstream-ready, or stop at no-go if it's upstream #1615's refresh rewrite.
2. [`02-window-is-focused-format-variable.md`](02-window-is-focused-format-variable.md) (in progress): a
   `%{window-is-focused}` format variable on its own upstream-bound branch, so Wicket's press
   costs one `aerospace` process. Wicket's brief 10 waits on it.

## Done

Archived in [`archive/`](archive/). They record what was asked for and why, not how the code works
now. For that, read `AGENTS.md` and the code.

None yet.

## Decisions already made

Don't relitigate these. They're in [docs/decisions/](../decisions/README.md),
one file each, and `docket decisions` lists them. If one turns out to be wrong in practice, stop
and say so.

## Not built

What's deliberately absent, so nobody flags it as missing. Point at `FUTURE.md` where it applies.

- A rewrite of upstream's root `README.md`, `dev-docs/` or user guide (`docs/guide.adoc`). They
  stay upstream's ([fork-docs-stay-out-of-upstream-files](../decisions/fork-docs-stay-out-of-upstream-files.md)).

## Future direction new work must not block

Each item is cheap to keep possible now and expensive to retrofit later.

- Sending a change upstream. Keep fork-only changes out of commits that might go to
  nikitabobko/AeroSpace, so a fix can be cherry-picked onto `upstream/main` cleanly.
