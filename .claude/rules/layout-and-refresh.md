---
paths:
  - "Sources/AppBundle/layout/**"
  - "Sources/AppBundle/normalizeLayoutReason.swift"
---

Before changing these files, read [Layout and refresh](../../docs/architecture/layout-and-refresh.md).

Refresh sessions (triggers, order of work, cancellation), macOS layout-reason normalization, frame computation (gaps, weights, accordion padding, hide-in-corner) and how frames reach windows, with per-session cost, for sessions chasing latency or changing layout.
