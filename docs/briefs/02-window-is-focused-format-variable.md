---
size: S
size-note: "one format variable, its tests and its doc line, written upstream's way"
status: in-progress
---
# Brief 02: `%{window-is-focused}` format variable

Read `AGENTS.md`, [`README.md`](README.md) and [commands](../architecture/commands.md) first.
[Running the fork](../guide/running-the-fork.md) covers the builds. No prerequisite briefs; it
doesn't depend on brief 01.

## Goal

Add a window format variable, `%{window-is-focused}`: a Boolean, true for the window that has
AeroSpace's global focus. It works anywhere window format variables work (`list-windows --format`,
`--json`, `echo`, `test`).

Why: Wicket, Logan's window switcher (`~/Code/personal/wicket`), runs two `aerospace` processes
per press today, `list-windows --focused` and the scope's listing. They cost about 65 ms each and
don't overlap, because the cost is starting the process. With this variable, one listing names
its focused window and Wicket's press costs one process. Wicket's brief 10 is waiting on this one.

`%{workspace-is-focused}` exists; the window counterpart doesn't. It's a small, general addition
that upstream might take, so it's written as an upstream PR.

## Decisions already made

- **On its own branch, cut from `upstream/main`** (Logan, 2026-11-02, Wicket's `/brief` round),
  per [upstream PRs branch from upstream/main](../decisions/upstream-prs-branch-from-upstream-main.md)
  and [window-is-focused goes on its own branch](../decisions/window-is-focused-goes-on-its-own-branch.md).
  Name it `window-is-focused`. Logan's installed build then carries it together with
  `slow-app-lag` (see Build order).
- [Upstream-bound changes follow upstream's rules](../decisions/upstream-bound-changes-follow-upstream-rules.md):
  the code, tests, doc line and commit message look like upstream's own.
- The name is `window-is-focused`, matching `workspace-is-focused` and `window-is-fullscreen`.

## Already checked (2026-11-02)

- Window format variables are `FormatVar.WindowFormatVar` in
  `Sources/Common/cmdArgs/impl/ListWindowsCmdArgs.swift:179`; `window-is-fullscreen` is line 181.
- They're resolved in `Sources/AppBundle/command/format.swift` around line 158:
  `case .windowIsFullscreen: .success(.bool(w.window.isFullscreen))`. The workspace one is
  `case .workspaceFocused: .success(.bool(globalFocus.workspace == w))`.
- `globalFocus.windowOrNil` is the focused window (`Sources/AppBundle/focus.swift`); it's what
  `list-windows --focused` uses (`ListWindowsCommand.swift:13`), which fails with
  `noWindowIsFocused` when it's nil.
- The full list of variable names is spelled out in error-message assertions in
  `Sources/AppBundleTests/command/TestCommandTest.swift:25,31` and `EchoCommandTest.swift:45`.
  Adding a case changes those strings.
- Format tests are in `Sources/AppBundleTests/command/FormatTest.swift`: `expandFormatVar` at
  line 154 and `formatToJson` at 326.
- The user doc is `docs/aerospace-list-windows.adoc:81`
  (`%{window-is-fullscreen}:: Boolean. …`). It's upstream's own file. Editing it belongs in an
  upstream-bound change, not in the fork's docs commits.
- `rg -n 'window-is-fullscreen'` finds every place a name is listed; check it for any spot
  this brief misses (grammar, shell completion).
- Logan's installed AeroSpace is `0.0.0-SNAPSHOT d6e7fff`, the `slow-app-lag` branch's release
  build. `aerospace subscribe` already exists upstream (since v0.21.0-Beta); it isn't part of
  this brief.

## Open questions

- **Open the upstream PR?** Default: no. Push the branch to `origin` and stop; Logan decides
  whether to open it.

## Shape

- `ListWindowsCmdArgs.swift`: `case windowIsFocused = "window-is-focused"` in `WindowFormatVar`,
  after `windowIsFullscreen`.
- `format.swift`: resolve it as `globalFocus.windowOrNil?.windowId == w.window.windowId` (or
  compare the windows, whichever reads like the code around it).
- Tests: an `expandFormatVar` case true for the focused window and false for another one, and
  the variable in a `formatToJson` case. Update the "Possible values" strings.
- `docs/aerospace-list-windows.adoc`: one line beside `window-is-fullscreen`'s.
- Run `./generate.sh` if anything it generates lists the variables, and `./format.sh`.
- The fork's [commands](../architecture/commands.md) page doesn't list the variables (checked
  2026-11-02), so it shouldn't need a change. If it does, that goes in a commit on `main`, not on
  the PR branch.

## Out of scope

- Brief 01's lag work and `slow-app-lag`.
- Any change to `list-windows` filtering or to `subscribe`.
- Wicket. Its brief 10 uses the variable.

## Build order

1. `git switch -c window-is-focused upstream/main`. Make the change, test, commit with an
   upstream-style subject (`list-windows: add %{window-is-focused}` or similar). Push to
   `origin`.
2. On `main`: the brief's report and any fork docs that change.
3. **Installing it is Logan's step,** since it replaces his running AeroSpace. In the report,
   give him the commands: a throwaway branch (or worktree) that merges `slow-app-lag` and
   `window-is-focused`, then the release build and `install-from-sources.sh --dont-rebuild`
   per [running the fork](../guide/running-the-fork.md). Don't run them yourself.

## Acceptance

- On the `window-is-focused` branch: `./swift-test.sh` passes, and so does `./test.sh` after
  committing (it fails on uncommitted files).
- With the debug build running (`./run-debug.sh`; it switches the installed AeroSpace off and
  back on, so **ask Logan once before starting it**), `.debug/aerospace list-windows
  --workspace focused --format '%{window-id} %{window-is-focused}'` prints `true` on exactly one
  line, the focused window's, and `false` on the rest. Focus another window and run it again:
  the `true` moves.
- `--json --format '%{window-id} %{window-is-focused}'` gives `"window-is-focused": true` as a
  JSON Boolean.
- `git log upstream/main..window-is-focused` shows only this change, with no fork docs commits.

By hand (Logan, after installing): `aerospace list-windows --focused --format
'%{window-is-focused}'` prints `true`.

Then stop. Push the branch to `origin` only; don't open an upstream PR or merge into `main`
without Logan.
