---
sources: ["Sources/AppBundle/mouse/"]
description: "How mouse drags and resizes are detected through AX notifications, how they move windows and recompute tiling weights, and how focus-follows-mouse picks a window, for sessions changing mouse behaviour or its per-event cost."
---
# Mouse

Move-with-mouse, resize-with-mouse and focus-follows-mouse. AeroSpace doesn't intercept the drag.
The app moves or resizes its own window, AeroSpace sees the AX notifications, rearranges the tree to
match, and keeps that window out of layout until the button comes up.

**History:** upstream's `git log` for these paths; `dev-docs/architecture.md` (upstream, stale: no mention of mouse)

Where the code is:

- `Sources/AppBundle/mouse/mouse.swift`: `currentlyManipulatedWithMouseWindowId`, `isLeftMouseButtonDown`, `isManipulatedWithMouse`, `mouseLocation` (y-flipped to the tree's top-left coordinates).
- `Sources/AppBundle/mouse/moveWithMouse.swift`: `movedObs`, floating and tiling drag, `swapWindows`, `CGPoint.findWindowRecursively` (point → tiled window hit test).
- `Sources/AppBundle/mouse/resizeWithMouse.swift`: `resizedObs`, weight recomputation, `resetManipulatedWithMouseIfPossible`.
- `Sources/AppBundle/mouse/focusFollowsMouse.swift`: the global mouse-moved monitor and window pick.
- Mouse-up detection lives in `Sources/AppBundle/GlobalObserver.swift` ([windows-and-focus.md](windows-and-focus.md)). The sessions these handlers run are described in [layout-and-refresh.md](layout-and-refresh.md).

## How it works

### Detecting a drag or resize

There is no event tap and no mouse-dragged monitor. Every registered AX window subscribes to kAXMovedNotification (`movedObs`) and kAXResizedNotification (`resizedObs`) on its app's thread. The callback resolves the native window id and pid there, then hops to the main actor:

1. Look up the `Window` by native id and pid.
2. `isManipulatedWithMouse(window)` is true only if all of these hold: the window isn't hidden in a corner, `NSEvent.pressedMouseButtons == 1` (left button and nothing else), no other window is currently manipulated, and `getNativeFocusedWindow` returns this window. That last check is one AX hop to the frontmost app. It only runs when the other conditions already hold, so in practice it costs a hop per notification while the left button is down.
3. If it's false, the notification is treated as an external change and calls `scheduleCancellableCompleteRefreshSession(.ax(notif))`. That includes any moves and resizes AeroSpace's own layout causes.
4. If it's true, cancel the previous move (or resize) task and start a new one that runs `runLightSession(.ax(notif))` with `moveWithMouse` (or `resizeWithMouse`) as the body.

`isLeftMouseButtonDown` is also read on app threads during window discovery, where it postpones registering new windows while the button is down. That keeps tabs dragged out of a window from being tiled mid-drag.

### End of manipulation

`NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp)` in `Sources/AppBundle/GlobalObserver.swift` calls `resetManipulatedWithMouseIfPossible()`. If a window was being manipulated, that clears `currentlyManipulatedWithMouseWindowId`, clears the saved before-resize weights on every node of every workspace, and schedules a complete refresh with `optimisticallyPreLayoutWorkspaces: true`. The same handler then, without suspending, either focuses another monitor's workspace through a light session (click on that monitor's desktop) or schedules another complete refresh. Either one cancels the pre-layout session before it starts, so the dragged window is laid out by that light session or by the replacement complete refresh. The code carries a todo about the duplicate sessions.

### Move with mouse (`moveWithMouse`)

Clears the closed-windows cache first, as any user layout change does.

- **Floating**: read the window center (one AX hop), take the visible workspace of the monitor under it, and `bindAsFloatingWindow` there. The guard `targetWorkspace != parent` compares the workspace with the window's `FloatingWindowsContainer`, so it is always true. Every move event rebinds the window, which moves it to the end of the floating children and raises MRU. That's harmless, but it's churn.
- **Tiling**: set `currentlyManipulatedWithMouseWindowId`, which makes `layoutRecursive` skip this window, and clear its physical rect. Find the target workspace from the mouse's monitor and the swap target with `findWindowRecursively(virtual: false)`, which reads the other windows' `lastAppliedLayoutPhysicalRect` in `tiles` containers and the MRU inhabited child in `accordion` ones.
  - Different workspace: bind into the swap target's nearest alive tiling parent, before or after it depending on which side of the target's center the mouse is along that parent's orientation. With no target, bind at index 0 of the root. The weight is `WEIGHT_AUTO`.
  - Same workspace with a target: `swapWindows`, which exchanges the two windows' parent, index and weight.
- Unconventional windows (macOS fullscreen, minimized, hidden-app, popup) are ignored.

The light session's layout reflows everything except the dragged window, so the other windows move live under the cursor. The dragged window snaps into its slot on mouse-up.

### Resize with mouse (`resizeWithMouse`)

Tiling windows only. Floating windows need no tree change.

1. Read the window's current AX rect and compare it with `lastAppliedLayoutPhysicalRect`. If there is no last rect, do nothing.
2. For each edge, `closestParent(hasInhabitedChildrenInDirection:withLayout: .tiles)` finds the nearest ancestor `tiles` container of the matching orientation that has an inhabited sibling on that side, and the window's ancestor index in it. The edge diff is positive when that edge moved outward:
   - left: `last.minX − rect.minX`, siblings `[0, ownIndex)`
   - right: `rect.maxX − last.maxX`, siblings `(ownIndex, count)`
   - up: `last.minY − rect.minY`, siblings `[0, ownIndex)`
   - down: `rect.maxY − last.maxY`, siblings `(ownIndex, count)`
3. Skip edges with `|diff| ≤ 5` (float drift) or no siblings on that side. Otherwise:
   - Every node from the window up to (not including) that ancestor whose parent is a `tiles` container of the same orientation gets `weightBeforeResize + diff`.
   - Every inhabited sibling on that side gets `weightBeforeResize` − diff ÷ count. The change is spread evenly over all of them, not just the adjacent one. If the range has zero inhabited siblings, the function returns early and never marks the window as manipulated.
4. Set `currentlyManipulatedWithMouseWindowId`, so layout stops writing this window's frame while the user drags.

`weightBeforeResize` is captured once per drag in per-node `userData`: the node's `lastAppliedLayoutVirtualRect` extent (the gap-free size, which matches the pixel-unit weights `layoutTiles` leaves behind), falling back to the current weight. Every resize event recomputes from that baseline plus the total diff since the drag started, so diffs don't accumulate. The baseline is cleared on mouse-up.

### Focus follows mouse

`syncFocusFollowsMouse(config)`, called from config reload (`Sources/AppBundle/command/impl/ReloadConfigCommand.swift`), installs or removes `NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved)`. A code comment notes the callback doesn't seem to fire while the button is down, which suits drags. On each event:

1. Cancel the previous `focusFollowsTask` and start a new one.
2. `isAxWindowUnderMouse` runs `AXUIElementCopyElementAtPosition` on the system-wide element, off the main actor (`@concurrent`). It stops only if the hit element is neither a window nor has a parent window, which filters out the menu bar and its menus. A failed lookup (no element) continues. The check itself can't be cancelled.
3. On the visible workspace of the mouse's monitor, walk floating windows in MRU order and read each one's AX rect, a serial awaited hop per window. The first rect that contains the point wins.
4. Otherwise run `findWindowRecursively(virtual: false, fullscreenCoversAll: true)` on the tiling tree. An AeroSpace-fullscreen MRU window covers everything.
5. `runLightSession(.focusFollowsMouse)` with `focusWindow()` and `nativeFocus()` as the body.

The `.focusFollowsMouse` light session skips layout, workspace GC, normalization and the follow-up complete refresh. It still does the focused-window AX hop at its start, and runs `nativeFocus()` a second time if the focus changed (the second call cancels the first's pending AX job).

## Rules worth keeping

- **Hit tests read the last layout, not live AX.** Tiled windows are found through `lastAppliedLayoutPhysicalRect`, which is stale while a light session is mid-flight and `nil` for fullscreen and dragged windows. Floating windows are the exception: they're read live, one hop each.
- **Each drag event runs a full light session.** Every kAXMoved or kAXResized during a drag costs a focused-window hop in `isManipulatedWithMouse`, the session's own focus hop, two `refreshModel_nonCancellable` passes, a full `layoutWorkspaces()` (frame writes for every visible tiled window, plus corner writes for every window on hidden workspaces), and a newly queued complete refresh that the next event cancels. Per-event task cancellation (`moveWithMouseTask` and `resizeWithMouseTask`) is the only throttling.
- **`currentlyManipulatedWithMouseWindowId` must be cleared on mouse-up.** While it's set, layout ignores that window and `isManipulatedWithMouse` rejects every other window. The only reset path is the global left-mouse-up monitor.
- **Resize math assumes `tiles` and pixel weights.** Accordion ancestors are skipped by `closestParent(withLayout: .tiles)`, and `setWeight` would die on them. If weights ever stop being pixel extents after layout, the virtual-rect baseline stops matching.
- **Keep `isLeftMouseButtonDown` meaning "left only".** It's `pressedMouseButtons == 1`, and window discovery relies on it as well.
- **Not unit-tested.** Both `moveWithMouse` and `resizeWithMouse` carry "todo cover with tests".
