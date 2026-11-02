---
description: "%{window-is-focused} goes on its own branch cut from upstream/main, and Logan's install merges it with slow-app-lag"
decided: 2026-11-02
by: "Logan"
covers: ["Sources/Common/cmdArgs/impl/ListWindowsCmdArgs.swift", "Sources/AppBundle/command/format.swift"]
---
# window-is-focused goes on its own branch

## Choice

The `%{window-is-focused}` format variable is built on a branch named `window-is-focused`, cut
from `upstream/main`, so it can go upstream as a PR on its own. Logan's installed build is a
merge of it and `slow-app-lag`.

## Why

Wicket (`~/Code/personal/wicket`) needs it to answer a switcher press with one `aerospace`
process instead of two. Chosen over putting it on `slow-app-lag` (simplest path to the installed
build, but it gets tangled with the lag work) and over the fork's `main` (which carries the docs
commits). From Wicket's `/brief` Parley round, 2026-11-02; the brief is
[02](../briefs/02-window-is-focused-format-variable.md).
