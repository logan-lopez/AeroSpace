---
size: L
size-note: "a spike with live runs against Godot and Moonlight, whose AX behavior isn't pinned"
status: awaiting-review
---
# Brief 01: Godot and Moonlight lag spike

Read `AGENTS.md`, [`README.md`](README.md),
[windows and focus](../architecture/windows-and-focus.md) (especially Unresponsive apps) and
[layout and refresh](../architecture/layout-and-refresh.md) (especially What one complete refresh
costs) first. [Running the fork](../guide/running-the-fork.md) covers the debug build. No
prerequisite briefs.

## Goal

With Godot (the editor, its project list, or a game run from it) or Moonlight (the streaming
window) running, all of AeroSpace lags: workspace switches, commands and hotkeys take seconds
instead of feeling instant. Logan sees it whether that window is on the workspace he's on or on
another one. Find out where the time goes, and fix it if the fix is local.

**This is a spike.** It ends in one of:

- **Go, fixed:** the stall is named with numbers, a local fix lands on an upstream-ready branch,
  and before/after numbers show it.
- **No-go:** the stall is the structural one upstream tracks as
  [#1615](https://github.com/nikitabobko/AeroSpace/issues/1615) (the complete refresh waiting on
  every app in `refreshAllAndGetAliveWindowIds` and `normalizeLayoutReason`), and no local change
  removes it. The report names the evidence and recommends a `brief-plan` for the reactive
  rewrite.

**Kill criteria.** Stop and report, without a fix, if any of these trips:

- The lag doesn't reproduce on the fork's build with Godot or Moonlight running (it reproduces on
  the installed 0.21.3; see Already checked). That would mean upstream fixed it in the 131 commits
  since, and the report says so with the numbers from both builds.
- One session ends without a stall named with trace or timing evidence.
- The only fix that works breaks a Project value in upstream's `README.md` (a private API beyond
  `_AXUIElementGetWindow`, say).

## Decisions already made

- **Spike first; land the fix in this brief only if it's local.** A rewrite of how the complete
  refresh waits on apps (#1615) is out of this brief. Logan, 2026-11-01
  ([decision](../decisions/slow-app-lag-spike-lands-only-a-local-fix.md)).
- **The fix is upstream-bound.** Its code goes on a branch cut from `upstream/main`, in
  upstream's style, so it can become a PR. Logan, 2026-11-01
  ([upstream-prs-branch-from-upstream-main](../decisions/upstream-prs-branch-from-upstream-main.md),
  [upstream-bound-changes-follow-upstream-rules](../decisions/upstream-bound-changes-follow-upstream-rules.md)).
- **Both visible and hidden matter.** Logan sees the lag whether the Godot or Moonlight window is
  on the workspace he's on or hidden on another (Logan, 2026-11-01). Measure both.

## Already checked

All 2026-11-01.

- **Installed AeroSpace** is 0.21.3-Beta (`d56e1637`, `aerospace --version`). The fork's `main` is
  `v0.21.3-Beta-131-gc8dd8c2f` (`git describe`): 131 commits ahead, none of them aimed at this
  ("Native tabs WIP", OpaqueWindowId, `getWindowLevel: don't block main thread`).
- **Logan's config floats both apps.** `~/.aerospace.toml` runs `layout floating` on
  `on-window-detected` for `org.godotengine.godot` (lines 32–35) and for
  `com.moonlight-stream.Moonlight` (the games/streaming rule, lines 126–129). So their windows go
  through `layoutFloatingWindow` when visible and `hideInCorner` when not. The root layout is
  accordion with `accordion-padding = 16` and zero inner gaps.
- **Installed versions:** Godot 4.7.2 (`/Applications/Godot_mono.app`; 4.3–4.5 and plain Godot
  are installed too, all `org.godotengine.godot`), Moonlight 6.2.0. macOS 27.0. Two displays: a
  3440×1440 ultrawide (main) and the built-in 3456×2234 Retina.
- **Godot's project list sat at 98% CPU** a few seconds after launch (`ps`, pid 22163).
- **Upstream history.** #218 (Godot lag on workspace switch) was closed as fixed in 0.18.1 by the
  thread-per-app model. #1615 (open, updated 2026-07-11) is the maintainer's own write-up: "Open
  some heavy application (e.g. Godot)" and window detection crawls, because the main actor
  awaits every app thread. #1287 (open) proposes skipping the hide-in-corner AX work on a
  workspace with a single tiling window. `AXUIElementSetMessagingTimeout` was set to 1 s in
  `6bb3f23c` and dropped in `535e4864` ("Now, we probably don't need it"); nothing calls it now
  (`rg MessagingTimeout Sources/`).
- **The CLI reply waits for the whole light session.** `Sources/AppBundle/server.swift:90`
  returns the answer from inside `runLightSession`, which lays out before returning
  (`Sources/AppBundle/layout/refresh.swift`). So `time aerospace workspace <name>` measures what
  Logan feels, minus the follow-up complete refresh. It works against the installed release
  build with no build of ours.
- **Where a floating window waits.** `layoutFloatingWindow`
  (`Sources/AppBundle/layout/layoutRecursive.swift:77`) awaits `getAxRect` on every layout pass,
  serially across floating windows (the call site at line 34 carries "todo make it parallel").
  `hideInCorner` (`Sources/AppBundle/tree/MacWindow.swift:135`) awaits `getAxRect` the first time
  a window hides, and `getAxSize` on every pass when the monitor's hide corner is bottom-left, then
  rewrites the position every pass whether or not the window has moved.
- **Signposts exist.** `signposter` (`Sources/AppBundle/util/appBundleUtil.swift:6`) is
  `OSSignposter(subsystem: aeroSpaceAppId, category: .pointsOfInterest)`. Intervals:
  `runLightSession` and `runHeavyCompleteRefreshSession` (`refresh.swift:30`, `:64`), and every
  AX `get` and `set` (`Sources/AppBundle/util/accessibility.swift:346`, `:356`) tagged with the
  attribute and the app thread token (`AxAppThreadToken.idForDebug`). The debug build's subsystem
  is `bobko.aerospace.debug` (`Sources/Common/appMetadata.swift:3`). Nothing measures how long a
  job waits in an app thread's queue: the AX signposts time the call, not the wait.
- **xctrace** 27.2 is installed, with the `os_signpost`, `Points of Interest`, `Hangs`,
  `Swift Tasks` and `Time Profiler` instruments, and `record --all-processes`, `--attach`,
  `--instrument`, `--time-limit`, plus `export --toc` and `--xpath` (`xcrun xctrace help`). The
  table schema names for export weren't checked: run `export --toc` on a first trace.
- **This machine can't build the fork yet.** `bash` first on `PATH` is 3.2 and swiftly isn't
  installed (`/opt/homebrew/bin/bash` and `swiftly` are both missing; `.swift-version` is 6.4.2).
  The guide's Before the first build has the steps. Logan installs them.
- **The terminal has no Accessibility permission.**
  [`assets/01/axprobe.swift`](assets/01/axprobe.swift) (times read-only AX calls into a pid, run
  with `swift axprobe.swift <pid>...`) got `kAXErrorAPIDisabled` (-25211) from Moonlight and
  `kAXErrorCannotComplete` (-25204) from Godot. The debug server asks for the permission on
  kitty's behalf anyway; once it's granted, the probe tells whether Godot and Moonlight are slow
  at AX on their own.

## Open questions

- **What does Moonlight need to be doing?** Logan says the streaming window, not the host list.
  Default: Logan starts a stream when the run reaches Moonlight; the implementer measures with
  and without a stream running.
- **Is the fix also worth a per-app timeout?** `AXUIElementSetMessagingTimeout` per app element
  would bound a hung call, but upstream dropped the global one. Default: don't add it unless the
  trace shows single AX calls into Godot or Moonlight taking longer than a second.

## Shape

Two halves: measure, then fix if local.

### Measure

1. **Raw AX latency, outside AeroSpace.** Run `axprobe.swift` against the running Godot (project
   list, then the editor with a project open, then a running game) and Moonlight (streaming).
   This says whether each app is slow at AX at all, and which attributes.
2. **Baseline on the installed build.** With Godot and Moonlight quit, then with each one running,
   time a series of switches with the installed CLI: something like 20 ×
   `time aerospace workspace <A>` / `<B>` alternating, where A and B are workspaces Logan picks,
   once with the app's window on A and once with it on a third workspace. Record median and max.
   This needs no build and gives the before numbers for the release build.
3. **Trace.** Record the same series with
   `xcrun xctrace record --instrument os_signpost --instrument 'Points of Interest' --all-processes --time-limit 60s --output <path>`
   (add `Hangs` or `Time Profiler` if the main thread looks busy rather than waiting). Export
   with `xctrace export --toc`, then `--xpath` for the signpost table, and reduce it with a script
   to: light-session durations, complete-refresh durations and their count per second while idle,
   and AX call durations per attribute per app thread.
4. **Name the stall.** The question the trace answers is where a slow light session spends its
   time. The candidates, from the architecture pages; confirm or rule out each with numbers:
   - **Floating reads.** `layoutFloatingWindow`'s awaited `getAxRect` per floating window,
     serial, every pass. Both apps are floating in Logan's config.
   - **Hidden-window reads and writes.** `hideInCorner`'s `getAxSize` on every pass (bottom-left
     corner only: check which corner each monitor gets) and its position write on every pass.
   - **Queueing behind the app's backlog.** An awaited hop waits in the app thread's FIFO behind
     the previous complete refresh's job, `normalizeLayoutReason`'s hops and frame writes. The
     AX signposts don't show the wait; if the numbers don't add up, add a temporary signpost
     interval around `runInLoop`'s enqueue-to-resume in `Sources/AppBundle/runLoop.swift`, in its
     own commit.
   - **A refresh storm.** AeroSpace's own position writes to a hidden or floating window may come
     back as `kAXMoved`/`kAXResized`, each scheduling another complete refresh
     (layout-and-refresh, Rules worth keeping). Count complete refreshes per second while idle
     with the app open.
   - **The frontmost hop.** `getNativeFocusedWindow` at the start of every session, when Godot or
     Moonlight is frontmost.
   - **The #1615 path.** `refreshAllAndGetAliveWindowIds` and `normalizeLayoutReason` waiting on
     the slow app in the complete refresh. This one is the no-go outcome if it's the cause.

   Godot's editor opens docks and dialogs as separate windows, so count its windows
   (`aerospace list-windows --all`): every per-window hop multiplies by that.

### Fix, if local

Which fix depends on what step 4 finds. Directions that fit "local", for the implementer to
choose between with numbers, not a list to do all of:

- Stop awaiting the slow app on the light session's path: for a floating window, do the read and
  the conditional move in one fire-and-forget job on the app thread (capturing the monitor rects
  it needs), so main doesn't wait; for a hidden window, keep the size from the first hide instead
  of reading it every pass, and skip the position write when the window is already in that
  corner.
- Don't re-send a frame or corner position that hasn't changed since the last pass, if a storm
  is the cause. This touches every app, so it needs a reason it's safe for apps that move
  themselves (a `kAXMoved` on the window clears the "already there" state, say).
- Whatever the trace points at instead, provided it stays inside the files below and upstream's
  Project values.

Files the fix may touch: `Sources/AppBundle/layout/layoutRecursive.swift`,
`Sources/AppBundle/layout/refresh.swift`, `Sources/AppBundle/tree/MacWindow.swift`,
`Sources/AppBundle/tree/MacApp.swift`, `Sources/AppBundle/runLoop.swift`. Keep the Rules worth
keeping on both architecture pages (AX only on the app's thread, never block main on an app
thread, don't skip the mouse-manipulated check). A unit test where the code allows it (layout
isn't unit-tested, per layout-and-refresh); otherwise the numbers and Logan's hand checks are
the test.

### Branches and where things land

- Code: a branch cut from `upstream/main`, named for what it fixes (for example
  `slow-app-floating-layout`). Upstream's commit style: short imperative subjects, scope prefix
  where it fits. A temporary diagnostic signpost goes in its own commit, so it can be dropped
  before a PR or kept if it earns its place.
- Docs: the report, trace summaries and any reduction scripts go on `main` under
  `docs/briefs/assets/01/`. Raw `.trace` bundles stay out of git (they're large); keep them in the
  scratchpad and summarize. If the fix makes a sentence on
  [layout-and-refresh](../architecture/layout-and-refresh.md) or
  [windows-and-focus](../architecture/windows-and-focus.md) untrue, fix it on `main` in the same
  session.

## Out of scope

- The #1615 reactive rewrite of `refreshAllAndGetAliveWindowIds` and `normalizeLayoutReason`. If
  it's the cause, that's the no-go.
- The three suspected upstream bugs in the briefs README's loose ends (the `windowLevelCache`
  latch, `Int32ExitCode.succ`, quit blocking). Note them in the report if the trace shows one in
  play; don't fix them here.
- Changing Logan's config (`~/.aerospace.toml` is a dotfile). If un-floating Godot or Moonlight
  turns out to dodge the lag, say so in the report as a workaround.
- Opening the upstream PR. The branch is PR-ready; Logan decides when to send it.

## Build order

1. Ask Logan to install bash 5 and swiftly if they're still missing (guide, Before the first
   build), and confirm `./build-debug.sh` builds.
2. Ask Logan once before the desktop runs (below), then take the probe numbers and the
   installed-build baseline.
3. Run the fork's debug build (`./run-debug.sh`; it switches the installed AeroSpace off and back
   on at Ctrl-C) and confirm the lag reproduces there. If it doesn't, stop: kill criterion.
4. Trace, reduce, name the stall. **Stop here for Logan** with the numbers and the fix you'd make,
   or the no-go case. One message, then go on with his answer.
5. Fix on the upstream branch, rebuild, re-measure the same series, and write the report.

## Acceptance

Runnable:

- On the fix branch, `./swift-test.sh` passes and `./lint.sh` passes. (`./test.sh` also runs
  `script/check-uncommitted-files.sh`, so commit first or run the steps by hand.)
- The report has a before/after table for the same switch series: median and max
  `time aerospace workspace` latency, and median light-session duration from the trace, for
  (a) neither app running, (b) Godot editor open on the current workspace, (c) on another
  workspace, (d) Moonlight streaming on the current workspace, (e) on another. **Go** means (b)
  to (e) after the fix are within 20%, or 10 ms, whichever is larger, of (a).
- The report counts complete refreshes per second while idle with each app open, before and
  after.
- `git log upstream/main..<fix-branch>` shows only code commits, no `docs/` paths.

**Desktop runs.** The probe, the baselines and the debug server switch workspaces, start and
stop AeroSpace, and need Godot open and a Moonlight stream running. Ask Logan once before the
first run, saying it takes about as long as the switch series and needs him to start the
Moonlight stream.

By hand, Logan, on the debug build from the fix branch:

- Workspace switching with the Godot editor and a running game open feels like it does with
  Godot quit, with Godot both on the current workspace and on another.
- The same with a Moonlight stream running.
- Floating Godot and Moonlight windows come back where they were after switching away and back,
  and a hidden one doesn't peek onto the screen.
- Moving a floating Godot window to the other monitor's workspace still carries it across, as
  `layoutFloatingWindow` does now.

Then stop. Ask Logan before merging or pushing anything, and before opening the upstream PR.

## Report

**Outcome: go, fixed.** The stall is local, not #1615: light sessions awaited AX reads on
floating and newly hidden windows, and apps that answer AX about once per frame (Godot, and
Moonlight under load) couldn't keep up with the session rate a status bar generates. Two
commits on `slow-app-lag` (from `upstream/main`) remove those awaits; with both, Godot and
Moonlight switches land inside the no-app range. Not pushed or merged.

### Built

- **Branch `slow-app-lag`** (worktree at `../AeroSpace-fix`), on `upstream/main` `7c0f987c`:
  - `64246aba Temporary: public signpost messages and runInLoop queue wait interval`
    (`refresh.swift`, `accessibility.swift`, `runLoop.swift`). Diagnostics only: makes the
    signpost messages public (attribute, app, event) and adds a `runInLoop wait` interval from
    enqueue to start. Drop it before a PR.
  - `eda788df layoutFloatingWindow: don't await the window rect` (`layoutRecursive.swift`,
    `MacApp.swift`, new `AppBundleTests/layout/FloatingWindowLayoutTest.swift`). The read and the
    conditional move to the workspace's monitor run as one job on the app thread
    (`MacApp.layoutFloatingWindow`), coalesced per window in `floatingLayoutJobs`, cancelled
    where `setFrameJobs` are. It's separate from `setFrameJobs` so it can't cancel
    `unhideFromCorner`'s pending write, which is queued just before layout; FIFO order on the app
    thread keeps unhide → read → fullscreen frame as before. The geometry is a pure function,
    `floatingWindowTopLeftOnWorkspaceMonitor`, with four unit tests.
  - `d6e7fff5 hideInCorner: don't await the window rect when it's already known`
    (`MacApp.swift`, `MacWindow.swift`). The first hide uses `lastAppliedLayoutPhysicalRect` for a
    tiling window, or `MacWindow.lastKnownFloatingRect` (reported back to main by the floating
    layout job) for a floating one, and falls back to the awaited read only when neither is
    known.
- **On `main`**, under `docs/briefs/assets/01/`: `switch-series.py` (timed switch series, with
  `--load` for a sketchybar-like load, `--warmup`, `--timeout`), `run-scenario.sh` (installed
  build: idle, then series, under an all-process signpost recording), `fork-series.sh` (fork
  debug build: start, place an app's windows with `PLACE`, loaded series, optional attached
  `TRACE`, stop with SIGINT), `reduce-trace.py` (OSSignpostIntervals → session and AX numbers;
  `--long` for a timeline). Traces stayed in the session scratchpad.

### How the stall works

- **Godot answers one AX request per frame.** `axprobe.swift`: every call, even a bare position
  read, took 13–14 ms at the project list; ~300 ms per call for the unfocused editor in the fork
  traces; ~400 ms (up to 1 s) under AeroSpace's backlog. Moonlight answers in 0.1–8 ms when
  probed alone, streaming or not, but its calls ran 0.2–1.9 s inside one recorded run.
- **Every light session awaited it.** `layoutFloatingWindow` awaited `getAxRect` (two calls) for
  each floating window on a visible workspace; `hideInCorner` awaited it on a window's first
  hide. Light sessions are never cancelled.
- **Sketchybar sets the session rate.** Each workspace or focus change makes Logan's sketchybar
  run `list-workspaces`, `list-windows --all` and `list-windows --focused` (and it polls
  `list-windows --focused` every second). Each is a light session plus a complete refresh. The
  installed build ran ~5 light sessions and ~4.6 complete refreshes per second during a plain
  switch series with no slow app open.
- **The queue grows without bound.** With the Godot editor floating on the current workspace,
  reads arrived faster than Godot answered: the installed AeroSpace wedged with 200 CLI calls
  queued. `sample` showed main idle in its run loop and the Godot app thread 100% inside
  `MacApp.getAxRect`. Quitting Godot drained it.
- **Ruled out or not the cause:** the #1615 path (the complete refresh's waits are cancellable
  and weren't what CLI calls waited on); the bottom-left `getAxSize` (workspaces 1, 2 and 4 are on
  the ultrawide, which hides bottom-right; only C and M on the built-in hide bottom-left); a
  Godot- or Moonlight-induced refresh storm (none: idle with Godot open and no input, the fork
  ran 0.36 complete refreshes/s before and none after). A storm from *other* apps is real, see
  Follow-ups.

### Numbers

Installed 0.21.3 (release build, real sketchybar load, no recorder), switching 1↔2:

| | median | max |
| --- | --- | --- |
| (a) neither app | 79–137 ms | 197 ms |
| Godot project list floating on 1 | 759 ms | 3.6 s |
| (b) Godot editor floating on 1 | wedged for minutes | – |
| (d) Moonlight streaming, floating on 1 | 79–159 ms; one run 1.6–8.2 s per hide | 8.2 s |
| (d′) Moonlight streaming, tiled on 1 | 129 ms | 205 ms |

Fork debug builds, before = `64246aba`, after = `d6e7fff5`, 20 switches after 6 warm-up, with
the sketchybar-like load (`fork-series.sh`; sketchybar itself only talks to the installed
server). Median (max), ms:

| | before | after |
| --- | --- | --- |
| (a) neither app | 298 / 635 / 1006 (2909) over three runs | 263 / 398 / 451 (2024) over three runs |
| (b) Godot editor floating on 1 | 2172 (3511) | **236 (242)** |
| (c) Godot editor floating on 4 | 480 (774) | **245 (2265)**, the first 8 switches 0.56–2.3 s, then ≤ 285 |
| (d) Moonlight streaming, floating on 1 | **wedged**: first switch > 20 s | **614 (2691)**, settling to 400–660 |
| (e) Moonlight streaming, floating on 4 | 639 (1037) | **289 (445)** |

After the first commit alone, (b) was 363 (1489): switches to 1 ~190 ms, switches to 2 still
0.5–1.5 s, which the trace put on `hideInCorner`'s awaited first-hide read queued behind the
previous floating read. The second commit closes that.

Light-session median from a trace: after (b) 151 ms (`after2-b`). The other cells weren't traced
(Logan, 2026-11-01: CLI numbers are enough).

Complete refreshes per second:

| | installed, idle with sketchybar | fork, idle, no input |
| --- | --- | --- |
| (a) | 0.9–1.0 | not measured |
| Godot editor on 1 | not measured (wedged) | before 0.36, after 0 |
| Moonlight streaming on 1 | 2.2–3.5 | not measured |

**Go criterion.** (b) to (e) after the fix sit inside (a)'s run-to-run range on the same build
(263–451 ms median after, 298–1006 before). (a) on these unoptimized debug builds under load is
too noisy for a strict "within 20% of (a)": the honest reading is that Godot and Moonlight no
longer add measurable latency, except (d)'s 400–660 ms steady state, which is at the top of the
(a) range.

### Deviations

- **Step 3's repro check moved into step 5.** The fork build's "before" run is the repro check:
  the code path is identical in `upstream/main`, and it gave before and after numbers from the
  same build configuration. (b) and (d) reproduce (and wedge) on it, so the kill criterion didn't
  trip.
- **The second fix (hideInCorner)** wasn't in Logan's first call ("only if (c)/(e) miss"); the
  trace put the remaining (b) cost there, and Logan said do it (2026-11-01).
- **Fork measurements use a simulated load and explicit placement.** The debug server doesn't
  get sketchybar's calls, so `switch-series.py --load` sends the same three queries per switch
  plus a 1 s poll. A fresh debug server also re-assigns windows to visible workspaces, so
  `fork-series.sh` moves the app to the scenario's workspace first. My first fork (b)/(c) runs
  missed that and were discarded.
- **Debug configuration, not release.** A `-c release` build takes the installed app's id and
  socket without switching it off. The stall is time spent waiting on AX, not CPU, so the
  comparison holds; absolute numbers are higher than the installed release build's.
- **Recorder artifact.** An all-process `os_signpost` recording can stall the threads it
  records: the 8 s floating-Moonlight run happened only under one, and two runs without a
  recorder right after were clean. Series ran without a recorder after that; fork traces attach
  to the one process.
- **Architecture pages on `main` describe `main`'s code**, which the fix doesn't change until the
  branch merges, so they got branch notes next to the affected sentences instead of rewrites.

### Defaults taken

- Moonlight: measured with a stream running (and the host list idle for the AX probe).
- No per-app `AXUIElementSetMessagingTimeout`: single calls never took a second outside a backlog
  (the editor's probe max was 1 s while AeroSpace was wedged against it).

### Acceptance

- `./swift-test.sh` passes on the fix branch (the new class: 4 tests, 0 failures, run by name;
  the script hides passing lines). `./lint.sh` passes: 0 files formatted, swiftlint clean,
  periphery "No unused code detected". `./test.sh` not run (it needs a committed tree and runs
  `generate.sh`; the steps were run by hand).
- Before/after table for (a)–(e): above. Median light-session time from a trace only for after
  (b); the rest waived by Logan.
- Complete refreshes per second while idle: above; Moonlight idle on the fork not measured.
- `git log upstream/main..slow-app-lag`: three commits, all under `Sources/`; no `docs/` paths.

### Size

Sized L, this session XL (114 active min, 114 wall, 0 compactions), from `docket sessions`.
The live runs ran long: the recorder artifact, the debug server's window placement and the
debug-build noise each cost a round of re-measuring.

### Spot checks for Logan

Run the fix branch's debug server from its worktree (bash 5 and swiftly first on `PATH`):
`cd ~/Code/forks/AeroSpace-fix && PATH=/opt/zerobrew/bin:$HOME/.swiftly/bin:$PATH ./run-debug.sh`,
then Ctrl-C to hand back to the installed AeroSpace. Your hotkeys go to the debug server while it
runs; sketchybar keeps talking to the installed one (switched off), so its bar won't update.

- Switching with the Godot editor and a running game open feels like Godot quit, with Godot on
  the current workspace and on another.
- The same with a Moonlight stream.
- Floating Godot and Moonlight windows come back where they were after switching away and back;
  a hidden one doesn't peek onto the screen. Also: drag a floating window, then switch away
  quickly and back. The known risk is it returning to its pre-drag spot.
- Moving a floating Godot window to the other monitor's workspace (C or M) still carries it
  across.

### Docs updated

- `docs/architecture/layout-and-refresh.md`: branch notes on the floating container and
  `hideInCorner` sentences.
- `docs/architecture/windows-and-focus.md`: Unresponsive apps now describes the runaway queue,
  with a branch note.
- `docs/guide/running-the-fork.md`: Accessibility goes to the app at the top of the process chain
  (not always kitty) and the macOS 27 pane name; the debug server re-places windows; don't build
  `-c release` into `.debug`.
- `~/Dev/dotfiles/.claude/CLAUDE.md` (uncommitted, for Logan to land): bash 5 and swiftly live in
  `/opt/zerobrew/bin` after `/bin` on `PATH`; sessions under another app need that app granted TCC.

### Follow-ups

- **Read-only CLI commands run a full light session and a complete refresh**
  (`Sources/AppBundle/server.swift`). A status bar polling `list-*` multiplies AeroSpace's load
  several times over. Skipping the follow-up refresh (or the layout) for read-only commands is a
  candidate second upstream PR; it's a behavior change upstream would want to weigh (Logan:
  follow-up only).
- **Self-induced refresh storm from other apps.** One fork run had 146 complete refreshes
  triggered by `kAXMoved` from Chrome, kitty and inn: AeroSpace's own frame writes echoing back
  (layout-and-refresh, Rules worth keeping). The brief's "don't re-send an unchanged frame"
  direction would cut it; not needed for this fix.
- **The frontmost hop remains.** With Godot focused, every session still starts with
  `getNativeFocusedWindow` on Godot's thread. It didn't show in the after numbers, but a slower
  app would.
- **Bottom-left hiding still awaits `getAxSize` every pass** (workspaces on the built-in display).
- **The temporary diagnostics commit** should be dropped before the PR; the `runInLoop wait`
  interval earned its place in this spike and could be proposed separately.
- **Sketchybar workaround** (config, not this repo): fewer queries per event, or no 1 s poll,
  would have softened the stall on the installed build.
- **The (d) steady state** (400–660 ms after) is at the top of (a)'s range; worth a look if
  Moonlight still feels slow on the hand check.

### After the report: diagnostics reverted (2026-11-02)

`64246aba` is reverted on `slow-app-lag` by `d8a1a354`, a revert rather than a rewrite because the
branch was already on `origin`. The three files it touched match `upstream/main` again. An upstream
PR should cherry-pick `eda788df` and `d6e7fff5` onto a fresh branch from `upstream/main`, which
leaves the commit and its revert behind. The `runInLoop wait` interval is still in `64246aba` if
it's proposed separately. `slow-app-lag` is merged into `personal`, the branch the installed build
comes from ([decision](../decisions/installed-build-comes-from-personal.md)).
