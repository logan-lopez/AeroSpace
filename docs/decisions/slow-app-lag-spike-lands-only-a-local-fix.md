---
description: "The Godot/Moonlight lag is a spike first: it lands a fix only if the fix is local, and the #1615 refresh rewrite is a separate plan"
decided: 2026-11-01
by: "Logan"
covers: ["docs/architecture/layout-and-refresh.md", "docs/architecture/windows-and-focus.md"]
---
# Slow-app lag spike lands only a local fix

## Choice

The first brief on the lag Godot and Moonlight cause
([brief 01](../briefs/01-godot-moonlight-lag-spike.md)) measures before it changes anything. If
the stall is on a path a local change removes (the awaited AX reads for floating and hidden
windows in a light session's layout, a self-induced refresh storm, or similar), the brief lands
that fix on a branch from `upstream/main` with before/after numbers. If the stall is the one
upstream tracks as [#1615](https://github.com/nikitabobko/AeroSpace/issues/1615) (the complete
refresh waiting on every app in `refreshAllAndGetAliveWindowIds` and `normalizeLayoutReason`),
the brief stops at a no-go, and the reactive rewrite gets its own plan.

## Why

Chosen over a diagnosis-only spike with the fix in a later brief, and over going straight at
the #1615 rewrite as a plan. Logan's config floats both apps, which puts their windows on
smaller awaited paths that may be the whole story; a rewrite of how refresh waits on apps is
expensive and should only start once a trace says it's needed. The fix aims upstream, per
[upstream-prs-branch-from-upstream-main](upstream-prs-branch-from-upstream-main.md).

Logan's answer in brief 01's Parley round, 2026-11-01.
