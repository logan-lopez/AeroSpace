---
size: S
size-note: "one format variable, its tests and its doc line, written upstream's way"
status: awaiting-review
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

## Report

### Built

On branch `window-is-focused`, cut from `upstream/main` (`7c0f987c`) and pushed to `origin`. One
commit, `5b02d47f Add %{window-is-focused} format variable`:

- **Commands:** `case windowIsFocused = "window-is-focused"` after `windowIsFullscreen` in
  `WindowFormatVar` (`Sources/Common/cmdArgs/impl/ListWindowsCmdArgs.swift`). It resolves in
  `Sources/AppBundle/command/format.swift` as
  `.success(.bool(globalFocus.windowOrNil == w.window))`, which reads like `workspaceFocused`'s
  `globalFocus.workspace == w`. `Window` is `Hashable`, so it compares the windows directly.
- **Tests:** `FormatTest.testExpandWindowIsFocused` is true for the focused window and false for
  another one on the same workspace. `testFormatToJsonSingleObject` focuses its window and checks
  `"window-is-focused": true` as a JSON Boolean. The "Possible values" strings in
  `TestCommandTest` (2) and `EchoCommandTest` (1) are updated.
- **Upstream docs:** ``%{window-is-focused}:: Boolean. `true` if the window has focus`` sits under
  `window-is-fullscreen`'s line in `docs/aerospace-list-windows.adoc` and
  `docs/aerospace-test.adoc`, worded like `workspace-is-focused`'s.

`./generate.sh` and `./format.sh` changed nothing: no generated file lists the variables.

On `main`: `28140c72 Brief 02: %{window-is-focused} format variable` commits the brief, its
decision and the two README entries. They were uncommitted when the session started, and the
brief had to be committed somewhere to hold this report. Then this report and the retag.

### Deviations

- **`docs/aerospace-test.adoc` gets the line too.** The brief named only
  `aerospace-list-windows.adoc`, but `rg` showed `test`'s page lists the same window variables.
- **Commit subject:** `Add %{window-is-focused} format variable`, not the brief's
  `list-windows: ...`. The variable works in `test`, `echo` and `--json` too, and upstream's
  scoped subjects name a file or script, not a command.

### Defaults taken

- **Open the upstream PR?** No. The branch is pushed to `origin` only.

### Acceptance

- `./swift-test.sh` on `window-is-focused`: **passed.** A filtered run confirmed the two new or
  changed tests pass (64 tests in the three classes, 0 failures).
- `./test.sh` after committing: **passed** (build with warnings as errors, tests, lint,
  periphery "No unused code detected", generate, clean tree).
- Debug-build `list-windows --workspace focused --format '%{window-id} %{window-is-focused}'`
  and the `--json` variant: **not run.** Logan OK'd the debug run. The server built and started
  but never opened its socket (`Connection refused`). It was waiting on Accessibility for
  `inn Stories.app`, the app this session runs under. Logan turned it on, the server still
  didn't answer, and per his answer I skipped the check. I stopped it with SIGINT, and the
  installed AeroSpace answered afterwards. The JSON Boolean is covered by
  `testFormatToJsonSingleObject`.
- `git log upstream/main..window-is-focused`: **only `5b02d47f`**, no fork docs commits.

### Size

Sized S, this session M (36 active min, 36 wall, 0 compactions). The time went to builds and to
waiting on the debug server, not to the change.

### Spot checks for Logan

Installing replaces your running AeroSpace, so I didn't run any of this. From the main checkout:

```sh
git worktree add ../AeroSpace-install -b install-lag-and-focus slow-app-lag
cd ../AeroSpace-install
git merge --no-ff window-is-focused
PATH=/opt/zerobrew/opt/ruby@3.4/bin:/opt/zerobrew/bin:$HOME/.swiftly/bin:$PATH
./build-release.sh --codesign-identity "Developer ID Application: Logan Lopez (CC63JS5AYR)"
./install-from-sources.sh --dont-rebuild
```

Then, as [running the fork](../guide/running-the-fork.md) says, quit the old server from its menu
and start the new one. Check:

- `aerospace list-windows --focused --format '%{window-is-focused}'` prints `true`.
- `aerospace list-windows --workspace focused --format '%{window-id} %{window-is-focused}'`
  prints `true` on exactly one line. Focus another window, run it again, and the `true` moves.
- `aerospace list-windows --workspace focused --json --format '%{window-id} %{window-is-focused}'`
  gives `"window-is-focused": true` unquoted.

Delete the throwaway branch and worktree when you're done:
`git worktree remove ../AeroSpace-install && git branch -D install-lag-and-focus`.

### Docs updated

None of the fork's. The commands page and the guide don't list format variables (checked again).
Upstream's two adoc pages changed on the PR branch only.

### Follow-ups

- **The debug server under inn Stories.** With Accessibility on for `inn Stories.app`, the debug
  server still didn't open its socket. Cause unknown. The grant might only take effect for a
  process started after it, or the debug binary might need its own entry. `run-debug.sh` also
  printed `tccutil: No such bundle identifier "bobko.aerospace.debug"`. Worth one retry with a
  fresh `./run-debug.sh` before the next brief that needs a live check. If it turns out to be a
  machine fact, it belongs under `## This machine` in the dotfiles clone's `.claude/CLAUDE.md`.
- **Upstream PR.** Open it from `origin/window-is-focused` against `nikitabobko/AeroSpace:main`
  when you decide to.
