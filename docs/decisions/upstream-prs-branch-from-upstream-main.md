---
description: "The fork's main carries its docs and merges upstream in; upstream PR branches are cut from upstream/main"
decided: 2026-11-01
by: "Logan"
covers: []
---
# Upstream PRs branch from upstream/main

## Choice

The fork's `main` is upstream's `main` plus the fork's docs commits, and upstream is merged into it
(not rebased, so nothing is force-pushed). The `upstream` remote points at
`https://github.com/nikitabobko/AeroSpace`. A branch meant as a PR to upstream is cut from
`upstream/main`, or has its commits cherry-picked onto it, so it carries no docs commits.

## Why

Chosen over a long-lived `fork` branch with `main` as a pure mirror, and over committing to `main`
with no upstream PRs. The fork's main purpose may end in an upstream PR, so PR branches have to be
clean. Keeping docs on `main` means sessions work where they start.

Logan's answer in brief-init's Parley round, 2026-11-01.
