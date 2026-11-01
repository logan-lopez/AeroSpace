---
sources: ["Sources/AppBundle/focus.swift", "Sources/AppBundle/focusCache.swift", "Sources/AppBundle/getNativeFocusedWindow.swift", "Sources/AppBundle/GlobalObserver.swift", "Sources/AppBundle/runLoop.swift", "Sources/AppBundle/windowLevelCache.swift", "Sources/AppBundle/initAppBundle.swift", "Sources/AppBundle/tree/MacApp.swift", "Sources/AppBundle/util/accessibility.swift", "Sources/AppBundle/util/AxSubscription.swift", "Sources/AppBundle/util/ThreadGuardedValue.swift", "Sources/AppBundle/util/AwaitableOneTimeBroadcastLatch.swift", "Sources/AppBundle/util/CompletableFuture.swift", "Sources/AppBundle/util/AxUiElementMock.swift", "Sources/AppBundle/util/axTrustedCheckOptionPrompt.swift", "Sources/AppBundle/util/dumpAxRecursive.swift", "Sources/AppBundle/util/appBundleUtil.swift", "Sources/Common/model/AxAppThreadToken.swift", "Sources/PrivateApi/"]
description: "The accessibility layer, thread-per-application model, AX and NSWorkspace observation, caches, focus reconciliation and startup, for sessions touching window observation, focus or performance."
---
# Windows and focus

How AeroSpace talks to other apps through the macOS Accessibility (AX) API, which threads those calls
run on, how it learns that something changed, and how its own focus is kept in step with macOS focus.
Every refresh session ([layout-and-refresh.md](layout-and-refresh.md)), every command
([commands.md](commands.md)) and the tree ([tree-model.md](tree-model.md)) sit on top of this layer.

**History:** upstream's `git log` for these paths (the thread-per-application model is upstream issue
131, first landed as "Implement the first draft of thread-per-application model"); `dev-docs/architecture.md`
(upstream, stale, says nothing about this layer)

Where the code is:

- `Sources/AppBundle/tree/MacApp.swift`: one `MacApp` per process, owning its AX thread, its `AXUIElement`s,
  observers and every AX read/write AeroSpace performs. The tree side of windows lives in
  `Sources/AppBundle/tree/MacWindow.swift`, which delegates all AX work here.
- `Sources/AppBundle/runLoop.swift`: `Thread.runInLoop` / `runInLoopAsync` and `RunLoopJob`, the only way
  work reaches an app thread.
- `Sources/AppBundle/util/ThreadGuardedValue.swift`, `Sources/Common/model/AxAppThreadToken.swift`: runtime
  thread confinement for AX objects.
- `Sources/AppBundle/util/AxSubscription.swift`: `AXObserver` lifetime and notification registration.
- `Sources/AppBundle/util/accessibility.swift`: typed AX attributes (`Ax.*`), `get` and `set` with signposts,
  `containingNativeWindowId()`, and the startup permission wait.
- `Sources/PrivateApi/`: a header-only module declaring `_AXUIElementGetWindow` (AX element to `CGWindowID`).
- `Sources/AppBundle/GlobalObserver.swift`: NSWorkspace notifications and the global left-mouse-up monitor.
- `Sources/AppBundle/getNativeFocusedWindow.swift`, `Sources/AppBundle/focusCache.swift`,
  `Sources/AppBundle/focus.swift`: reading macOS focus, syncing it into AeroSpace focus, and the focus model
  plus on-focus-changed callbacks.
- `Sources/AppBundle/windowLevelCache.swift`: `CGWindowListCopyWindowInfo`-backed window level lookup.
- `Sources/AppBundle/util/AwaitableOneTimeBroadcastLatch.swift`, `Sources/AppBundle/util/CompletableFuture.swift`:
  the two synchronization primitives used around app threads.
- `Sources/AppBundle/initAppBundle.swift`: server startup. `Sources/AppBundle/util/appBundleUtil.swift`:
  termination handler, `CancellationMode`, the `signposter`.
- `Sources/AppBundle/util/dumpAxRecursive.swift`: AX dumps for `debug-windows`;
  `Sources/AppBundle/util/AxUiElementMock.swift`: lets unit tests feed JSON in place of `AXUIElement`.

## How it works

### Threads

| Where | What runs there |
|---|---|
| Main actor | All tree/focus state, refresh and light sessions, NSWorkspace notification handlers, `MacApp`'s bookkeeping (`windowIdMapping`, `setFrameJobs`, `windowsCount`, `lastFocusedNativeWindowOpaqueId`, `thread`). These `MacApp` fields carry no actor annotation; they're main-actor-only by convention. |
| One `Thread` per `MacApp` (named `AxAppThread` plus the app's pid and bundle id) | Every AX call for that process, and the callbacks of that process's `AXObserver`s. The thread sits in `CFRunLoopRun()` for the app's lifetime. |
| Swift concurrent pool | `computeCache()` in `Sources/AppBundle/windowLevelCache.swift` (`@concurrent`), so `CGWindowListCopyWindowInfo` stays off main. |

The point of the model is that AX calls are synchronous IPC into the target process and block for as
long as that process takes to answer. Putting each process on its own thread means a slow app stalls only
its own queue, and the main actor only ever *awaits* AX results. The package builds with
`NonisolatedNonsendingByDefault`, so `MacApp`'s nonisolated `async` methods run on the caller's actor, which
is the main actor in practice.

### Hopping to an app thread

`Sources/AppBundle/runLoop.swift` uses `perform(_:on:with:waitUntilDone: false)` to enqueue a
`RunLoopAction` on the app thread's run loop. Jobs on one app thread run strictly one at a time, FIFO.

- `runInLoop(cm, body) async throws -> T`: suspends the caller in a checked continuation until the job runs.
  On task cancellation it only flips `RunLoopJob.isCancelled`; the continuation is resumed when the app
  thread dequeues the job, which then throws `CancellationError` before running the body. So a cancelled
  awaiter stays suspended until every job ahead of it on that thread has finished. With `.nonCancellable`, any
  error from the body is `die()`.
- `runInLoopAsync(job:body)`: fire-and-forget; returns the `RunLoopJob` so callers can cancel it. A job already
  cancelled when dequeued is skipped. Bodies check `job.checkCancellation()` between AX calls, so a cancel
  stops a multi-call job at the next boundary, never mid-call.
- `RunLoopAction` captures the `refreshSessionEvent` task-local at enqueue time and re-binds it on the app
  thread, so `isStartup` and friends read correctly inside jobs.
- `MacApp` wraps these as `withWindow` (await, looks up the `AXUIElement` by native id on the app thread,
  returns `nil` for unknown ids or a destroyed app) and `withWindowAsync` (returns `RunLoopJob.cancelled` when
  there is no thread or no mapping).

### Thread confinement

`axTaskLocalAppThreadToken` is a `@TaskLocal` bound once per app thread (to the pid) when the thread starts.
`ThreadGuardedValue` and `AxSubscription` capture the token at creation and `check` it on every access (`AxSubscription`
also in `deinit`); touching them from another thread crashes. `MacApp` keeps `axApp`, `appAxSubscriptions` and
`windows` (`[UInt32: AxWindow]`) in `ThreadGuardedValue`s. A `ThreadGuardedValue` must be `destroy()`ed on its
thread before `deinit` or it crashes, which is why the thread closure tears down subscriptions, windows, then
`axApp` after `CFRunLoopRun()` returns.

### Registering an app

`MacApp.getOrRegister(nsApp)` (main actor):

1. Returns `nil` for loginwindow (`lockScreenAppBundleId`) and for AeroSpace's own pid (AX requests to
   yourself crash).
2. Returns the cached `allAppsMap[pid]`, or awaits the in-flight registration's latch in `wipPids[pid]`.
3. Otherwise starts the app thread, which creates `AXUIElementCreateApplication(pid)` and one `AXObserver`
   subscribed to `kAXWindowCreatedNotification`, `kAXFocusedWindowChangedNotification` and
   `kAXMainWindowChangedNotification`, all routed to `refreshObs`. It then hops to main to set
   `allAppsMap[pid]`, clear `wipPids[pid]` and signal the latch, in that order.
4. If any observer creation or `AXObserverAddNotification` fails, `bulkSubscribe` returns `[]`, the app is
   stored as `nil`, and the thread exits without a run loop. Nothing remembers the failure: the next refresh
   (and, while the app is frontmost, every session's `getNativeFocusedWindow`) calls `getOrRegister` again and
   spawns a fresh thread.

Callers: `getNativeFocusedWindow` (frontmost app, any activation policy) and
`MacApp.refreshAllAndGetAliveWindowIds` (every `.regular` app in `NSWorkspace.shared.runningApplications`).
Non-regular apps only enter `allAppsMap` by becoming frontmost, and once in, they get refreshed like the rest.

### AX notifications

Every `AxWindow` (one per known window) owns three more `AXObservers`, since `bulkSubscribe` makes one
observer per handler:

| Notification | Element | Handler | Effect |
|---|---|---|---|
| `kAXWindowCreated`, `kAXFocusedWindowChanged`, `kAXMainWindowChanged` | app | `refreshObs` | complete refresh |
| `kAXUIElementDestroyed`, `kAXWindowMiniaturized`, `kAXWindowDeminiaturized` | window | `refreshObs` | complete refresh |
| `kAXMoved` | window | `movedObs` | mouse-move light session if the window is being dragged, else complete refresh |
| `kAXResized` | window | `resizedObs` | mouse-resize light session if being resized, else complete refresh |

The run loop sources are added to the app thread's run loop, so callbacks fire on the app thread.
`refreshObs` hops straight to main; `movedObs` and `resizedObs` first call `containingNativeWindowId()` and
`AXUIElementGetPid` on the app thread ([mouse.md](mouse.md) covers the rest). "Complete refresh" means
`scheduleCancellableCompleteRefreshSession`, which cancels the previous scheduled session and starts a new
one: notifications are coalesced by cancellation, not debounced by time. All handlers bail if
`TrayMenuModel.shared.isEnabled` is false.

Layout calls `setAxFrame` for every visible tiling window on every layout pass, without comparing to the
previous frame ([layout-and-refresh.md](layout-and-refresh.md)). Any resulting `kAXMoved` or `kAXResized` on a
window not under mouse manipulation schedules another complete refresh.

### NSWorkspace and the mouse

`GlobalObserver.initObserver()` registers on `NSWorkspace.shared.notificationCenter` with `queue: .main`:

- `didLaunchApplication`, `didActivateApplication`, `didUnhideApplication`, `activeSpaceDidChange`,
  `didTerminateApplication` → complete refresh. `didActivateApplication` passes
  `optimisticallyPreLayoutWorkspaces: true`, so that session lays out once right after syncing focus and again
  at the end. Notifications whose app is loginwindow are dropped.
- `didHideApplication` → a light session that, with `automatically-unhide-macos-hidden-apps`, re-focuses the
  previous window if exactly one app is hidden (cmd-h rather than "hide others") and unhides every app.
- `NSEvent.addGlobalMonitorForEvents(.leftMouseUp)` → `resetManipulatedWithMouseIfPossible`, then either a
  light session focusing the clicked monitor's workspace (click on another monitor's desktop) or a complete
  refresh, which catches close-button clicks that `kAXUIElementDestroyed` misses and window detection deferred
  while the button was down.

There is no handler that registers or destroys an app directly. Launch and terminate only trigger a refresh;
the refresh registers new apps and garbage-collects ones whose `nsApp.isTerminated`.

### AX traffic of one refresh session

Every session, heavy or light, starts with `getNativeFocusedWindow`:
`NSWorkspace.shared.frontmostApplication` → `getOrRegister` → `runInLoop` on that app's thread reading
`kAXFocusedWindowAttribute` (registering an `AxWindow`, with its observers, if new) → main →
`MacWindow.getOrRegister`. Then `updateFocusCache`.

A complete refresh then calls `MacApp.refreshAllAndGetAliveWindowIds`:

1. `destroy()` apps whose process terminated: remove from `allAppsMap`, cancel their `setFrameJobs`, enqueue
   `CFRunLoopStop` on their thread, set `thread = nil` so later submissions no-op.
2. In a task group: register new `.regular` apps (sequentially, each `getOrRegister` is awaited inside the loop)
   and add one child task per app. Children are `@MainActor`, so they interleave on main while each awaits its
   own app thread. The group returns only when every app has answered.
3. Per app, one job on its thread: drop known windows whose `_AXUIElementGetWindow` now fails (skipped while
   loginwindow is frontmost), read `kAXWindowsAttribute` (only windows on the active macOS Space), register
   `AxWindow`s for new ids (not while the left mouse button is down, upstream issue 1001), and classify each
   known id as `.alive` (listed) or `.invisible` (not listed but still resolvable).
4. Back on main per app: `windowsCount`, the native-tab swap heuristic (`nonidempotentNativeTabSwapHeuristic`
   remaps the opaque id when exactly one tab disappears and one appears), native id → `OpaqueWindowId`, and
   cancellation of `setFrameJobs` for vanished windows.

`refresh()` then garbage-collects dead `MacWindow`s and calls `MacWindow.getOrRegister` for every id,
sequentially. Known ids are a dictionary hit. A new window costs, in order: `getAxRect` (hop),
`getWindowLevel`, `getAxUiElementWindowType` (hop, several attribute reads; heuristics in
`Sources/AppBundle/model/AxUiElementWindowType.swift`), the closed-windows-cache restore and
`on-window-detected` callbacks. Later in the session, `normalizeLayoutReason` awaits `isMacosFullscreen`
and usually `isMacosMinimized` for every window on every workspace, one window at a time, plus window level
and `isWindowHeuristic` for every popup; hiding windows of invisible workspaces awaits `getAxRect` per window not yet
hidden, plus `getAxSize` when hiding into the bottom-left corner. All of these except window level (a `windowLevelCache` lookup) are separate main → app-thread round trips.

### Writes

- `setAxFrame`: cancels the window's previous job in `setFrameJobs` and enqueues a new one, so only the latest
  frame per window survives a backlog. The job reads `AXEnhancedUserInterface` on the app element and turns it
  off around the write if set (disables animations; borrowed from yabai/Rectangle), then sets size, position,
  size (order matters, upstream issues 143 and 335). `setNativeFullscreen` and `setNativeMinimized` share
  `setFrameJobs`.
- `nativeFocus`: one global `MacApp.focusJob`, cancelled by the next call. Fast path with no AX at all when
  displays don't have separate Spaces or there is one monitor, *and* the window is the app's
  `lastFocusedNativeWindowOpaqueId` or the app has one window: just `nsApp.activate`. Otherwise a job sets
  `AXMain`, performs `AXRaise`, then activates. The fast path exists for apps slow at basic AX requests (Godot).
- `closeAndUnregisterAxWindow`: presses the close button via AX, async.
- All writes are no-ops under `--read-only` (`AXUIElement.set` returns `false`).

### Focus

AeroSpace focus is `_focus: FrozenFocus` (window id, workspace name, monitor id). `globalFocus` resolves it
to a `LiveFocus` on every read; if the window and workspace no longer agree, the workspace wins.
`setFocus(to:)` marks MRU, sets the monitor's visible workspace and stores the new frozen focus. Focusing a
window only changes AeroSpace state; macOS focus is a separate step.

- **macOS → AeroSpace** (`updateFocusCache`, run at the start of every session): ignores popups; if the
  natively focused window id differs from `lastKnownNativeFocusedWindowId`, calls `focusWindow()` on it. So
  native focus overrides AeroSpace focus only when native focus *changes*. When it hasn't changed, AeroSpace's
  focus stands, which is what lets a command focus a window before macOS catches up. It also records the app's
  `lastFocusedNativeWindowOpaqueId`, used by the `nativeFocus` fast path.
- **AeroSpace → macOS**: `runLightSession` compares `globalFocus.windowOrNil` before and after the body and
  calls `nativeFocus()` on the new window if it changed. Heavy sessions don't, except via
  `MacWindow.garbageCollect` (re-focus after the focused window dies). The hide handler and focus-follows-mouse
  also call it directly.
- **Callbacks**: `checkOnFocusChangedCallbacks_nonCancellable` (called from `refreshModel_nonCancellable`, once
  per heavy session, twice per light session, and once after every command `Shell.run` executes) diffs against `_lastKnownFocus`, updates `prevFocus`
  (focus-back-and-forth) and `_prevFocusedWorkspaceName` (workspace-back-and-forth), and runs
  `on-focus-changed`, `exec-on-workspace-change` and `on-focused-monitor-changed` plus subscription broadcasts
  ([shell-and-callbacks.md](shell-and-callbacks.md)). Skipped during startup; a recursion guard stops callbacks
  that change focus from re-entering.

### Caches

| Cache | Key → value | Filled | Invalidated |
|---|---|---|---|
| `MacApp.allAppsMap` | pid → `MacApp` | `getOrRegister` | `destroy()` when `nsApp.isTerminated`, checked each complete refresh |
| `MacApp.wipPids` | pid → latch | registration start | registration end |
| `MacApp.windows` (app thread) | native id → `AxWindow` (element + observers) | focused-window read, refresh | rebuilt each refresh from the alive/invisible set |
| `MacApp.windowIdMapping` | `OpaqueWindowId` ↔ native id | first sight of a native id | never pruned, so `closedWindowsCache` can match windows re-detected after screen unlock |
| `windowLevelCache` `cache` | native id → `MacOsWindowLevel` | on a miss, rebuilt wholesale from `CGWindowListCopyWindowInfo(.excludeDesktopElements, .optionAll)` | only by the next miss, which replaces it wholesale |
| `lastKnownNativeFocusedWindowId` | last native focus | each session | each session |
| `MacApp.lastFocusedNativeWindowOpaqueId`, `windowsCount` | per app | each session / refresh | same |

They exist to avoid AX round trips: every attribute read is IPC into another process, and
`CGWindowListCopyWindowInfo` is expensive (the reason it was moved off main). Window titles, sizes,
fullscreen/minimized state and the window-type heuristics are not cached (the heuristics carry
`todo cache` comments in `MacWindow`).

`getWindowLevel` coordinates concurrent misses with a latch, but as written it sets `wip = nil` before
`await wip?.signalToAll()`, so the latch is never signaled. A caller that arrives while another call is
computing waits until its own task is cancelled; a `.nonCancellable` caller in that position (`debug-windows`
passes `.nonCancellable` for `--window-id` and for the first window when it starts recording) would not return.

### Unresponsive apps

No code calls `AXUIElementSetMessagingTimeout`, so every AX call is bounded only by the system default
messaging timeout, and AeroSpace has no timeout of its own on top. What a hung app does:

- Its app thread blocks in the current AX call. Every later job for that app (reads, `setAxFrame`,
  `nativeFocus`, the per-refresh job) queues behind it. Other apps' threads are unaffected, and the main actor
  is not blocked.
- A complete refresh can't finish: the task group waits for every app. The next trigger cancels it and starts a
  new one, but the cancelled one stays suspended until the hung thread drains, and the new one queues its own
  job behind the same call. The heavy session's `normalizeLayoutReason` and layout never run in the meantime (light sessions still lay out).
- If the hung app is frontmost, every session (including CLI commands and hotkeys via `runLightSession`)
  stalls at `getNativeFocusedWindow` before doing anything.
- A newly launched app that is slow to accept observer registration stalls the sequential registration loop in
  step 2, and with it the refresh.
- A cancelled job runs to its next `checkCancellation()`; a single AX call is never interrupted.
- On quit, `AppServerTerminationHandler.beforeTermination` calls `getAxRectForTermination` and
  `setAxFrameForTermination` for every window, which block the main thread (`CompletableFuture.blockingGet`,
  `DispatchSemaphore.wait`) until the app thread answers, one window at a time. It can hang for
  good: if the native id is missing from the app thread's `windows` map (a refresh job pruned it
  before main garbage-collected the `MacWindow`), `withWindowAsync` returns a live job without
  running the body, so the future or semaphore is never signalled.
- A hung app that isn't frontmost still stalls light sessions, which aren't cancelled: layout
  awaits `getAxRect` for every floating window on visible workspaces (`layoutFloatingWindow` in
  `Sources/AppBundle/layout/layoutRecursive.swift`), and `hideInCorner` awaits `getAxRect` for
  windows not yet hidden and `getAxSize` on every pass for bottom-left hiding
  (`Sources/AppBundle/tree/MacWindow.swift`). Commands wait behind it. With apps that answer
  AX about once per frame (Godot: 13 ms per call at the project list, ~300 ms for the
  unfocused editor) and frequent CLI calls (a status bar
  polling `list-*`), reads arrive faster than the app answers and the server stops responding
  for minutes ([brief 01](../briefs/01-godot-moonlight-lag-spike.md)). Branch `slow-app-lag`
  (not merged) removes the floating read and the first-hide read; the bottom-left size read
  remains.
- `on-window-detected` title matchers read the title with `.nonCancellable`, so a heavy session
  registering a window of a hung app can't be cancelled out of that wait.
- While the mouse is down, each moved or resized notification adds a frontmost-app hop through
  `isManipulatedWithMouse` (`Sources/AppBundle/mouse/mouse.swift`), which calls
  `getNativeFocusedWindow`.
- The `getWindowLevel` latch bug (Caches) can also hang the startup session, which is never
  cancelled, if another session misses the cache while startup is filling it.

### Startup

`initAppBundle()` (called from `Sources/AeroSpaceApp/AeroSpaceApp.swift`'s `init`) runs one main-actor task:
termination handler; CLI args (`--config-path`, `--read-only`, `-v`, `-h`); `waitForAccessibilityPermission_nonCancellable`
(polls `AXIsProcessTrusted` every second; after each failed prompted check (the first poll, or after the menu's permission button) it runs tccutil reset for the app id,
because macOS doesn't reset the grant when the signature changes); in debug builds, turns off the release
server and intercepts signals; loads the bundled default config (must succeed) then the user's; starts the
socket server ([client-server.md](client-server.md)); registers `GlobalObserver`; creates workspaces and
focuses each monitor's lowest-sorted workspace; runs `runHeavyCompleteRefreshSession(.startup, assumeCancellable: false,
layoutWorkspaces: false)`, which registers every regular app and assigns new windows to the workspace of the
monitor under their center (`isStartup` in `MacWindow.getOrRegister`); then a light session that picks tiles
(three or fewer root children) or accordion for the focused workspace and runs `after-startup-command`.

### Observability

`AXUIElement.get`, `set`, `containingNativeWindowId`, `runHeavyCompleteRefreshSession` and `runLightSession`
emit `OSSignposter` intervals (subsystem `aeroSpaceAppId`, category points of interest), tagged with the AX
attribute and the app thread token. They show up in Instruments' Points of Interest track.

## Rules worth keeping

- **AX only on the app's own thread.** Go through `withWindow`, `withWindowAsync` or `thread?.runInLoop`. The
  thread-guard checks crash otherwise, and calling AX from main would bring back the whole-UI stall the model
  exists to prevent.
- **Never block main on an app thread** outside termination. A semaphore or `blockingGet` on main turns one hung
  app into a hung window manager.
- **Destroy `ThreadGuardedValue`s on their thread before release.** `deinit` checks it; the destroy order after
  `CFRunLoopRun()` (subscriptions, windows, `axApp`) is deliberate.
- **Signal latches after clearing the "in progress" marker, and signal the latch you created.** `getOrRegister`
  sets `allAppsMap` and clears `wipPids` before signalling, so woken waiters and new callers both find the app. `windowLevelCache.swift`
  clears its marker and then signals through it, which signals nothing.
- **Cancellation is cooperative at AX-call granularity.** Put `job.checkCancellation()` between AX calls in
  multi-call jobs, and don't expect a cancelled `runInLoop` to return before the thread reaches it.
- **Use `.nonCancellable` only where a crash is acceptable.** `runInLoop` dies on any error in that mode, and the
  startup session dies if cancelled.
- **Keep new per-refresh AX work out of the sequential paths.** Anything awaited per window in `refresh()`,
  `normalizeLayoutReason` or layout is a main → app-thread round trip in series, and a slow app stretches the
  whole session.
- **Don't treat a missing focused window as a focus change.** `updateFocusCache` only acts when the native id
  changes; feeding it `nil` just resets `lastKnownNativeFocusedWindowId`.
- **Don't register lockscreen windows or yourself.** loginwindow is filtered in three places (`getOrRegister`,
  the refresh job, `GlobalObserver`); self-AX crashes.
- **`kAXWindowsAttribute` only sees the active Space.** That's why windows missing from it are `.invisible`,
  not dead, as long as `_AXUIElementGetWindow` still resolves them.
