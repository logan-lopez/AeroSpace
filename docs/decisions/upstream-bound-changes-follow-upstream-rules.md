---
description: "Changes that might go upstream follow CONTRIBUTING.md and the README's Project values"
decided: 2026-11-01
by: "Logan"
covers: ["Sources/", "CONTRIBUTING.md"]
---
# Upstream-bound changes follow upstream's rules

## Choice

A change that might be sent to nikitabobko/AeroSpace is written the way upstream would write it.
`CONTRIBUTING.md`'s rule is "read the room": the patch, the commit message and the tests look like
the repo's own. The root `README.md`'s Project values bind it too: no private APIs beyond
`_AXUIElementGetWindow`, never require disabling SIP, no GUI for configuration, practical features
over appearance ones.

A change meant only for the fork may break those values, but says so in its brief.

## Why

The fork is mainly for a performance investigation that may go upstream (Logan, 2026-11-01).
Upstream says maintainers can apply patches "with arbitrary modifications"; a patch that already
matches its style and values needs fewer.

Approved in brief-init's Parley round, 2026-11-01.
