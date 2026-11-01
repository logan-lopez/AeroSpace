# Briefs

Each brief is a self-contained handoff for a fresh session. New ones go here, numbered in order,
and move to `archive/` when they're done. Ideas that aren't scheduled yet are in
[`FUTURE.md`](FUTURE.md).

## Where things stand

*Updated 2026-11-01.*

- The fork's `main` is upstream's `main` (nikitabobko/AeroSpace) at `7c0f987c` (2026-11-01), plus
  these docs. It has no code changes of its own yet.
- The main reason for the fork is a performance issue Logan is digging into. It may go upstream.
  It needs a brief, starting with what the slowdown is and how to reproduce it.
- Nothing is open. The next step is `brief` for the first piece of work.
- The fork's docs live only in new paths, so merging upstream doesn't conflict. Upstream PRs branch
  from `upstream/main`, a remote added on 2026-11-01
  ([decisions](../decisions/README.md)).

## Open

In the order they should be done. A status tag follows the link when it isn't "not started".

None yet.

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
