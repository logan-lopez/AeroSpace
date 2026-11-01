---
paths:
  - "Sources/AppBundle/shell/**"
  - "Sources/Common/model/AeroSpaceEnvVars.swift"
---

Before changing these files, read [Shell and callbacks](../../docs/architecture/shell-and-callbacks.md).

AeroSpace's mini shell (lexer, parser, &&/||/;/|, eval), exec-and-forget and exec-on-workspace-change process spawning, the AEROSPACE_* env vars, and where each config callback is dispatched and what it costs, for sessions touching command strings, callbacks or scripting performance.
