---
description: "Logan's installed AeroSpace is built from a long-lived personal branch: upstream/main with his feature branches merged in, never rebased"
decided: 2026-11-02
by: "Logan"
covers: []
---
# The installed build comes from `personal`

## Choice

Logan's installed AeroSpace is a release build of the `personal` branch, in the worktree
`../AeroSpace-personal`. It starts from `upstream/main` and merges in each feature branch he wants
running (today `slow-app-lag` and `window-is-focused`) with `--no-ff`. When a feature branch or
`upstream/main` moves, it's merged in again, never rebased. The fork's docs stay on `main` and
aren't merged into `personal`, so `git log upstream/main..personal` is exactly what the build adds.

## Why

Logan wanted one build carrying every change made in the fork. A named branch replaces the
throwaway merge brief 02's report suggested, so the next feature joins the same build. Basing it on
`main` was turned down: the docs don't change the build, and `main` would need merging in again
every time they change. Named `personal` over `logan` (could be taken for his copy of `main`) and
`installed`. Logan's Parley answers, 2026-11-02, after brief 02.

Builds on [upstream PRs branch from upstream/main](upstream-prs-branch-from-upstream-main.md) and
[window-is-focused goes on its own branch](window-is-focused-goes-on-its-own-branch.md).
