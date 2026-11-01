---
sources: ["Sources/AppBundle/layout/", "Sources/AppBundle/normalizeLayoutReason.swift"]
description: "Refresh sessions (triggers, order of work, cancellation), macOS layout-reason normalization, frame computation (gaps, weights, accordion padding, hide-in-corner) and how frames reach windows, with per-session cost, for sessions chasing latency or changing layout."
---
# Layout and refresh

A refresh session is how the server reconciles its tree with what macOS reports, then pushes frames
back out to windows. Every hotkey, CLI command, AX notification and NSWorkspace notification ends up
in one, so this is where per-event latency and AX traffic add up.

**History:** upstream's `git log` for these paths; `dev-docs/architecture.md` (upstream, stale: its layout section is "todo")

Where the code is:

- `Sources/AppBundle/layout/refresh.swift`: `runHeavyCompleteRefreshSession`, `scheduleCancellableCompleteRefreshSession`, `runLightSession`, `refreshModel_nonCancellable`, the window sync in `refresh()`, `layoutWorkspaces` (hide and unhide), `refreshObs` (the AX callback for app and window notifications).
- `Sources/AppBundle/layout/layoutRecursive.swift`: frame computation per node type (`layoutTiles`, `layoutAccordion`, floating, fullscreen).
- `Sources/AppBundle/normalizeLayoutReason.swift`: moves windows in and out of the macOS fullscreen, minimized and hidden-app parking containers, and re-checks popups.
- Related: the AX threading and what each hop costs, in [windows-and-focus.md](windows-and-focus.md); the tree and its normalization, in [tree-model.md](tree-model.md); mouse-driven sessions, in [mouse.md](mouse.md).

## How it works

### Two session kinds

**Complete ("heavy") refresh**, `runHeavyCompleteRefreshSession`. Almost always started through `scheduleCancellableCompleteRefreshSession`, which cancels `activeRefreshTask` and starts a new main-actor `Task`. There is no delay or time-based coalescing: the newest event wins, the older task is cancelled but not awaited. In order:

1. Return if the server is disabled (`TrayMenuModel.shared.isEnabled`).
2. `getNativeFocusedWindow` (one hop to the frontmost app's AX thread, which may register a new window), then `updateFocusCache`.
3. If `optimisticallyPreLayoutWorkspaces`, run `layoutWorkspaces()` now, for fast visual feedback before the slow part. Passed for `didActivateApplication` and for the mouse-up reset after a drag. Layout then runs twice in that session.
4. `refreshModel_nonCancellable()`: `garbageCollectUnusedWorkspaces`, `forceAssignWorkspaces`, the focus-change callbacks (`on-focus-changed`, `exec-on-workspace-change`, `on-focused-monitor-changed`, which can run commands), and `normalizeContainers()` on every workspace.
5. `refresh()`: `MacApp.refreshAllAndGetAliveWindowIds` (registers new apps; one hop per app, run in parallel in a task group that waits for the slowest app), then marks and GCs every `MacWindow` whose id wasn't reported, then `MacWindow.getOrRegister` for every reported id, setting `lifeStatus` to `.alive` or `.invisible`. Known ids are a dictionary hit. New ids, one after another, do two awaited app-thread hops each (rect, window-type heuristics) plus a window-level lookup from a cached `CGWindowListCopyWindowInfo` snapshot (rebuilt off the main actor on a miss), then run `on-window-detected`. Then workspace GC again.
6. `gcMonitors()`, `updateTrayText()`, `SecureInputPanel.shared.refresh()`.
7. `normalizeLayoutReason()` (below).
8. `layoutWorkspaces()` (below).

`CancellationError` is swallowed if the session was cancellable. Any other error dies.

**Light session**, `runLightSession(event, guard, body)`. Wraps every command source: hotkeys (`Sources/AppBundle/config/HotkeyBinding.swift`), CLI requests (`Sources/AppBundle/server.swift`), menu bar, config auto-reload, the startup commands, the hide-app handler, mouse move and resize, and focus-follows-mouse. In order: cancel `activeRefreshTask`, then focused-window hop and `updateFocusCache`, `refreshModel_nonCancellable()`, `body()`, `refreshModel_nonCancellable()` again, tray and secure-input refresh. Then `layoutWorkspaces()`, `nativeFocus()` if the focused window changed, and **`scheduleCancellableCompleteRefreshSession(event)`**. A light session doesn't discover windows, beyond registering the focused one if it is new. Every non-focus-follows-mouse light session lays out once itself and then queues a full complete refresh, which lays out again. With `.focusFollowsMouse`, `refreshModel_nonCancellable` only runs focus callbacks (no GC, no normalization), and both the layout and the follow-up complete refresh are skipped.

Startup (`Sources/AppBundle/initAppBundle.swift`) runs one non-cancellable complete refresh with `layoutWorkspaces: false`. While `isStartup` is true, new windows go to the workspace of the monitor under their center, not to the focused workspace. Then a light session runs `after-startup-command`.

### What triggers a session

| Source | Session |
| --- | --- |
| Hotkey, CLI command, menu-bar action, config auto-reload | light, then complete |
| AX app notifications: window created, focused window changed, main window changed (`refreshObs`) | complete |
| AX window notifications: destroyed, miniaturized, deminiaturized (`refreshObs`) | complete |
| AX moved and resized (`movedObs`, `resizedObs`) | light (mouse move or resize, then complete) if the window is under mouse manipulation, else complete |
| NSWorkspace launch, unhide, active-space change, terminate | complete |
| NSWorkspace activate | complete with pre-layout |
| NSWorkspace hide | light, then complete |
| Global left-mouse-up | complete with pre-layout if a mouse drag just ended (cancelled before it starts by what follows), plus a light session (click on another monitor's desktop) or another complete one |
| Mouse moved (focus-follows-mouse on) | light `.focusFollowsMouse`: no layout, no complete refresh |

The notification wiring lives in `Sources/AppBundle/GlobalObserver.swift` and `Sources/AppBundle/tree/MacApp.swift`.

### Cancellation and interleaving

All tree work runs on the main actor. AX work runs on per-app threads, reached through `Thread.runInLoop` (`Sources/AppBundle/runLoop.swift`). A cancelled session stops at its next `checkCancellation()` or cancellable `runInLoop`, but:

- Cancelling doesn't wait for the old task. Two sessions can interleave on the main actor at `await` points.
- A cancelled `runInLoop` only resumes once the app thread reaches the queued job, which then throws. A session waiting on a hung or slow app stays alive until that app's thread drains. New sessions queue their own hops behind it on the same thread. There is no AX messaging timeout set anywhere in the code base, so a hung app means the macOS default timeout per call.
- `refreshModel_nonCancellable` (callbacks) and the synchronous parts of layout always run to completion.

### `normalizeLayoutReason`

For every window of every workspace (`allLeafWindowsRecursive`, so tiling, floating and already-parked windows), plus the global minimized container (normalized against `globalFocus.workspace`):

- `isMacosFullscreen` (one awaited AX hop), then `isMacosMinimized` (a second hop, only if not fullscreen). Hidden-app is `nsApp.isHidden`, used only when `automatically-unhide-macos-hidden-apps` is off.
- `.standard` window now in a macOS state: set `layoutReason = .macos(prevParentKind:)` and bind into the matching parking container (fullscreen and hidden-app per workspace, minimized global).
- `.macos` window no longer in any of those states: `exitMacOsNativeUnconventionalState` restores it as floating, re-tiles it next to the workspace's MRU window (not its old slot), or re-classifies it (popup or impossible prior kinds).

Then `validateStillPopups`: for every window in the global popup container, it calls `getWindowLevel` and `isWindowHeuristic` (one hop). If the window now looks like a real window, it is relaid onto `globalFocus.workspace` and `on-window-detected` runs.

All of this is a serial `for … try await` loop: 1–2 sequential main → app-thread → main round trips per window, every complete refresh, across all workspaces, visible or not.

### `layoutWorkspaces`

- Disabled server (reached from the light session that runs `enable off`): unhide every window and lay out every workspace, then return.
- Pick a hide corner per monitor. It probes points just outside the bottom-left and bottom-right corners (the extreme corner point weighted ×10), counts how many monitors contain each, and picks the side that overlaps fewer monitors. Ties go to bottom-right.
- For each monitor's visible workspace: `unhideFromCorner()` on every leaf, then `layoutWorkspace()`. Visible workspaces go first to reduce flicker.
- For every invisible workspace: `hideInCorner(corner)` on every leaf window. The first time, it reads the window rect (one awaited hop) to save its proportional position, and `lastFloatingSize` for floating windows. Bottom-left also reads the window size (one awaited hop) on every pass, to push the window left by its width. Then it sets the position only, leaving 1px on screen (0px offset for Zoom). `unhideFromCorner` writes a frame only for floating windows. Tiling windows get theirs from the layout pass.

### Frame computation (`layoutRecursive`)

- Workspace: rect = monitor `visibleRect` minus outer gaps (`visibleRectPaddedByOuterGaps`, per-monitor `ResolvedGaps`). The physical height passed down is `height - 1`, to work around macOS refusing full width on stacked monitors. The virtual rect is the full padded rect. The root tiling container is laid out first, then floating windows.
- Two rects per node: **physical** (real inner gaps) goes to `lastAppliedLayoutPhysicalRect`. **Virtual** (as if inner gaps were 0, an exact partition of the parent) goes to `lastAppliedLayoutVirtualRect`. Mouse hit-testing, `move-mouse` and resize-with-mouse read them ([mouse.md](mouse.md)).
- `tiles`: over `inhabitedChildren` only, delta = (extent − Σweight) ÷ count, and each child's weight becomes `weight + delta`. This **writes the model**: weights become pixel extents that sum to the container's extent. Inner gap `g` for the orientation: the first child starts at the container edge, every later child is offset by g÷2, and each child's extent is `weight − g`, except that the first and last children shrink by g÷2 less on their outer edge. A single child gets no gap. The virtual rect uses the full weight.
- `accordion`: every inhabited child gets the whole container rect minus padding along the orientation. With `p = accordion-padding`, the paddings (leading, trailing) are: sole child (0,0), first (0,p), last (p,0), the child just before the MRU child (0,2p), just after (2p,0), others (p,p). First and last take precedence. No inner gaps between accordion children. Children share the parent's virtual rect.
- Window: skipped entirely if it is `currentlyManipulatedWithMouseWindowId`. If `isFullscreen` (AeroSpace's own fullscreen) and it is the root container's `mostRecentWindowRecursive`, it gets the monitor `visibleRect` if `noOuterGapsInFullscreen`, else the gap-padded rect, and a `nil` physical rect. Otherwise `isFullscreen` is **reset to false** and the window gets its physical rect.
- Floating container: for each floating window, clear both rects and read its AX rect (one awaited hop each, serial, with the code's own "todo make it parallel"). If the window's center is on a monitor whose visible workspace isn't this one, move it to the same proportional position on this workspace's monitor, clamped and with its size kept. If `isFullscreen`, apply the fullscreen frame once and clear the flag.
- macOS parking containers and popups: nothing.

### Writing frames

`Window.setAxFrame` → `MacApp.setAxFrame(windowId, topLeft, size)`:

- Called on the main actor, it returns immediately. It cancels the window's pending job in `setFrameJobs` (a job not yet started is skipped, a running one stops at its next cancellation check) and enqueues a new job on the app's thread with `performSelector(onThread:waitUntilDone: false)`.
- On the app thread, `disableAnimations` reads `AXEnhancedUserInterface` on the app element and, if it's set, turns it off around the write. Then `setFrame` sets size, position, size again (the order matters for some apps, per issues 143 and 335 in the code comments), checking cancellation in between. Hide-in-corner writes position only. That's 4 AX calls per tiled window per layout, 6 when enhanced UI is on.
- Coalescing is per window only: the latest frame replaces a pending one. There is no batching across windows and no diff against the previous frame. Every layout pass re-sends every visible tiled window's frame and every hidden window's corner position. Writes for different apps run in parallel on their own threads. Within one app they're FIFO, and later awaited hops to that app (the next session's reads) queue behind them.

### What one complete refresh costs

For N windows across all workspaces and the minimized container, A apps, F floating windows on visible workspaces, H windows on invisible workspaces, P popups, T tiled windows on visible workspaces:

- Awaited, serial: 1 focus hop + the slowest app's refresh hop + several hops per newly seen window + N to 2N `normalizeLayoutReason` hops + P popup hops + F floating-rect hops + up to H hide hops (first hide, and every pass for bottom-left).
- Fire-and-forget: T frame writes (4–6 AX calls each) + H position writes, every pass, and twice with pre-layout.
- Main-actor CPU (normalization, traversals, `Workspace.all` sorting) is small next to that. With per-monitor gap values, each `ResolvedGaps` re-reads and sorts `NSScreen.screens` once per per-monitor value (up to six).
- A command costs a light session (one layout) plus this complete refresh. A burst of events cancels and restarts it, but every restart begins from step 1.
- Inside each app's refresh hop, every known window gets a `containingNativeWindowId()` AX call (skipped while the lock screen is frontmost), on every complete refresh (`refreshAllAndGetAliveWindowIds` in `Sources/AppBundle/tree/MacApp.swift`).
- Light sessions aren't tracked or cancelled by anything (only `activeRefreshTask` is), so two hotkey or CLI sessions can overlap at their `await`s.
- During a drag, the light session's layout moves the other windows. If macOS sends kAXMoved for those, each one schedules a complete refresh, since it isn't the manipulated window.

`signposter` intervals (`Sources/AppBundle/util/appBundleUtil.swift`) wrap both session kinds and every AX attribute get and set (`Sources/AppBundle/util/accessibility.swift`), so Instruments' Points of Interest track shows session spans and per-attribute AX latency by app thread.

## Rules worth keeping

- **Self-induced notifications aren't filtered.** AeroSpace's own frame writes can produce kAXMoved and kAXResized on the moved windows. Unless the mouse is manipulating that window, each one schedules another complete refresh, which re-sends all frames again. Whether this settles depends on apps not notifying on no-op writes. The code doesn't compare against `lastAppliedLayoutPhysicalRect` before writing.
- **Layout mutates the model.** `layoutTiles` rescales weights, every pass rewrites the `lastAppliedLayout*Rect`s, and `isFullscreen` is cleared on non-MRU tiling windows and after one pass on floating windows. Code that reads weights before and after a layout sees different numbers.
- **`normalizeContainers` runs before `refresh()` in a complete refresh.** A window GC'd in step 5 can leave an empty or single-child container that gets laid out in step 8 with a stale `.alive` status (a blank share of space) until the next session normalizes it.
- **Every serial `try await` in these loops is an app round trip.** Adding an AX read per window to `normalizeLayoutReason`, `layoutFloatingWindow` or `hideInCorner` multiplies by the window count on every event. Parallelizing per app (as `refreshAllAndGetAliveWindowIds` does) is the existing pattern.
- **Don't skip the mouse-manipulated check.** `layoutRecursive` must leave `currentlyManipulatedWithMouseWindowId` alone, or layout fights the user's drag.
- **New windows default to the focused workspace.** Outside startup, anything newly registered, any window coming back from minimized, and any popup promoted to a window lands on `globalFocus.workspace` ([tree-model.md](tree-model.md)).
- **Light sessions always queue a complete refresh** (except focus-follows-mouse). Making a command cheaper doesn't remove the full window sync that follows it.
- **Layout isn't unit-tested.** `TestWindow` doesn't implement `setAxFrame`, so verify layout changes by hand.
