---
sources: ["Sources/AppBundle/tree/", "Sources/AppBundle/model/", "Sources/Common/model/OpaqueWindowId.swift"]
description: "The window tree (node types, bind/unbind, weights, orientation, normalization, tombstones, MRU, monitors and visible workspaces, window IDs) and its invariants, for sessions changing how nodes are stored, created or moved."
---
# Tree model

The single mutable, main-actor-only object graph that says which window is where: monitors, workspaces,
tiling containers, windows, and parking containers for floating and macOS-native states. Every command,
the refresh session, layout and the mouse handlers read and mutate it directly.

**History:** upstream's `git log` for these paths (the tombstones and opaque IDs came in with the
"Native tabs WIP" series); `dev-docs/architecture.md` (upstream, stale: its tree section is "todo")

Where the code is:

- `Sources/AppBundle/tree/TreeNode.swift`: base class; children, weak parent, weight, per-node MRU, `bind`/`unbind`, last applied layout rects, user data.
- `Sources/AppBundle/tree/TreeNodeCases.swift`: the closed set of node classes as enums, and `getChildParentRelationOrNil`, the table of legal child/parent pairs.
- `Sources/AppBundle/tree/TreeNodeEx.swift`: traversal helpers (`allLeafWindowsRecursive`, `nodeWorkspace`, `nodeMonitorInfo`, `mostRecentWindowRecursive`, `closestParent`, `nearestAliveTilingParent`).
- `Sources/AppBundle/tree/TilingContainer.swift`: orientation, layout (`tiles`/`accordion`), container `lifeStatus`.
- `Sources/AppBundle/tree/shimContainers.swift`: `WorkspacesContainer`, `FloatingWindowsContainer` and the four macOS parking containers.
- `Sources/AppBundle/tree/tombstones.swift`: `WindowLifeStatus` and `TilingContainerLifeStatus`.
- `Sources/AppBundle/tree/normalizeContainers.swift`: flatten/remove-empty/opposite-orientation normalization.
- `Sources/AppBundle/tree/Window.swift`, `Sources/AppBundle/tree/MacWindow.swift`: window leaf; registration of new windows and where they get bound; GC of closed windows; hide-in-corner.
- `Sources/AppBundle/tree/Workspace.swift`, `Sources/AppBundle/tree/WorkspaceEx.swift`: name registry, GC, lazily created child containers.
- `Sources/AppBundle/tree/Monitor.swift`, `Sources/AppBundle/tree/MonitorEx.swift`, `Sources/AppBundle/tree/WorkspacesContainerEx.swift`: monitor nodes keyed by top-left corner, monitor rearrangement, visible workspace per monitor, stub workspaces.
- `Sources/AppBundle/tree/frozen/`: immutable snapshot of the whole world (`FrozenWorld`) used as the closed-windows cache.
- `Sources/AppBundle/model/`: value types around the tree: `MonitorInfo` (an NSScreen snapshot), `Rect`, `Json`/`OrderedJson`, `KnownBundleId`, the window/dialog/popup heuristics, `ServerEvent`.
- `Sources/AppBundle/tree/MacApp.swift` (the per-app AX thread) is covered in [windows-and-focus.md](windows-and-focus.md).

## How it works

### Shape

```
Monitor                                  (root; parent nil; held by pointToMonitor[topLeftCorner])
└─ WorkspacesContainer                   (visibleWorkspaceNameOrStale, prevVisibleWorkspaceName)
   └─ Workspace*                         (held by workspaceNameToWorkspace[name])
      ├─ TilingContainer (root)          0..1, created on first read of rootTilingContainer
      │  └─ TilingContainer | Window     any depth
      ├─ FloatingWindowsContainer        0..1, lazy ─ Window*
      ├─ MacosFullscreenWindowsContainer 0..1, lazy ─ Window*
      └─ MacosHiddenAppsWindowsContainer 0..1, lazy ─ Window*
macosMinimizedWindowsContainer           global root ─ Window*   (no workspace, no monitor)
macosPopupWindowsContainer               global root ─ Window*
```

- `TreeNode` is a class hierarchy with a closed set of subclasses. Code dispatches on it through `nodeCases`, `cases`, `windowParentCases` and `tilingTreeNodeCasesOrDie()`, all of which `die` on anything unexpected. `getChildParentRelationOrNil` is the full legality table; `bind` calls it and dies on an illegal pair.
- Roots are made by binding to `NilTreeNode.instance`, which leaves `parent == nil`. `Monitor`, the minimized container and the popup container are roots.
- Ownership: `_children` is strong and `_parent` is weak. Strong references outside the tree are `MacWindow.allWindowsMap` (windows), `workspaceNameToWorkspace` (workspaces), `pointToMonitor` (monitors), and the two global `let`s. An unbound container with no outside reference is freed immediately, and its children's `parent` turns `nil` (this is what `testChildParentCyclicReferenceMemoryLeak` in `Sources/AppBundleTests/tree/TreeNodeTest.swift` checks). `restoreClosedWindowsCacheIfNeeded` keeps `prevRoot` in a local for exactly this reason.

### Bind and unbind

`bind(to:adaptiveWeight:index:)` is the only way to attach a node, and it always detaches first:

1. Debug builds die if the new parent is a `TilingContainer` whose `lifeStatus != .alive`.
2. `unbindIfBound()` removes the node from the old parent's `_children` and `_mruChildren`, clears `_parent`, and stores the call stack in `unboundStacktrace` (shown if someone later unbinds twice).
3. If the target is `NilTreeNode`, it stops there.
4. Weight: `WEIGHT_AUTO` (-1) into a tiling parent becomes the mean weight of the parent's *inhabited* children along the parent's orientation, or 1 if there are none. Into any non-tiling parent it becomes `WEIGHT_DOESNT_MATTER` (-2). Any other value is stored as given.
5. Insert at `index` (`INDEX_BIND_LAST` = -1 appends), set `_parent`, and `markAsMostRecentChild()`.

It returns the old `BindingData(parent, adaptiveWeight, index)`, so swap and move are written as unbind → rebind with the other node's binding data (`swapWindows` in `Sources/AppBundle/mouse/moveWithMouse.swift`). `unbindFromParent()` dies if the node is already unbound.

Every bind raises MRU all the way to the root, including binds made by normalization, by window detection and by lazy container creation.

### Weights

`adaptiveWeight` is stored on the child, but only the parent gives it meaning (`getWeight`):

- Tiling parent with the same orientation: the stored `adaptiveWeight`.
- Tiling parent with the other orientation, or the root container: the parent's own weight in that orientation, recursively up to `Workspace.getWeight`, which is the monitor's `visibleRectPaddedByOuterGaps` dimension. `Monitor.getWeight` is the same.
- Floating, macOS-parked, popup, shim: `getWeight` dies.

`setWeight` dies unless the parent is a `tiles` container with the requested orientation. Weights are not ratios: `layoutTiles` adds (extent − sum) ÷ count to every inhabited child on each pass, so after one layout the children's weights sum to the container's pixel extent ([layout-and-refresh.md](layout-and-refresh.md)). Accordion children keep whatever weight they had.

### Orientation and layout

`TilingContainer` has `orientation` (`.h`/`.v`), `layout` (`.tiles`/`.accordion`; the string "list" parses as tiles), and `lifeStatus`. A new root container takes `default-root-container-orientation` (`auto` means at-least-as-wide-as-tall gives `.h`) and `default-root-container-layout`. In debug builds, setting `layout` on a container that isn't alive dies.

`changeOrientation` flips every `TilingContainer` from `self` up to the root when `enable-normalization-opposite-orientation-for-nested-containers` is on. Otherwise it sets only `self`.

### Tombstones (`lifeStatus`)

Windows: `.alive`, `.invisible` (the app still has the AX element with a valid window id but doesn't list it in `AXWindows`: other macOS Spaces, background native tabs), `.dead` (set by `refresh()` just before `garbageCollect`). Containers: `.alive`, `.deadOrInvisible` (no inhabited children), `.mustBeFlattened` (exactly one inhabited child plus tombstoned ones, so it can't be flattened without losing their slots).

"Inhabited" means alive, or `mustBeFlattened` for containers. Tombstoned nodes stay in `children` with their index and weight, but layout, `WEIGHT_AUTO`, sibling search (`inhabitedSiblingIndex`, `closestParent`), `findWindowRecursively` and `mostRecentInhabitedChild` skip them. `mustBeFlattened` containers are transparent: `nearestAliveTilingParent` walks through them and `resolvedThroughMustBeFlattenedRecursive` descends through them.

### Normalization

`Workspace.normalizeContainers()` runs for every workspace (not only visible ones, because commands take `--workspace` and `--window-id`) from `refreshModel_nonCancellable`. That is once per complete refresh, twice per light session, and once more after every command run through the shell, single or in a sequence (`Sources/AppBundle/shell/Shell.swift`), so a one-command hotkey or CLI request normalizes three times.

`unbindEmptyAndFlattenContainersRecursive`, with flattening (`enable-normalization-flatten-containers`) on:

- Root: if its only child is a `TilingContainer`, lift the grandchildren into the root, keeping their weights. Each is rebound at the index it had when unbound, which is 0 every time, so they land in reverse order. The root keeps its own orientation and layout. The root itself is never removed and is always marked `.alive`.
- Non-root with exactly one child, whatever that child's `lifeStatus`: replace the container with the child at the same index and weight, keeping the parent's MRU choice.
- Otherwise recurse, unbind the container if it has no children, and set `lifeStatus` from the inhabited-child count (1 → `.mustBeFlattened`, 0 → `.deadOrInvisible`).

With flattening off, only empty containers are removed. Then, if opposite-orientation normalization is on, `normalizeOppositeOrientationForNestedContainersRecursive` forces each alive container to the opposite of its parent. `mustBeFlattened` takes its parent's orientation and tombstones are skipped. The code's own todo on `unbindEmptyAndFlattenContainersRecursive` says its MRU effect and complexity are unclear.

Container `lifeStatus` is recomputed only here. Between normalizations, a container emptied by window GC still reads `.alive`.

### Floating and macOS-native placeholders

`Window.layoutReason` is `.standard` or `.macos(prevParentKind:)`. `normalizeLayoutReason` ([layout-and-refresh.md](layout-and-refresh.md)) moves windows into `MacosFullscreenWindowsContainer` (per workspace), `macosMinimizedWindowsContainer` (global) or `MacosHiddenAppsWindowsContainer` (per workspace) when macOS reports those states, and remembers the previous parent kind. On exit, `exitMacOsNativeUnconventionalState` rebinds as floating, or re-tiles with `relayoutWindow(forceTile: true)`, which places the window next to the workspace's MRU window, not in its old slot. Windows classified as popups sit in the global `macosPopupWindowsContainer` and get no layout. `isFloating` is true only for a `FloatingWindowsContainer` parent.

Where a new window goes (`unbindAndGetBindingDataForNewWindow`): `getAxUiElementWindowType` (`Sources/AppBundle/model/AxUiElementWindowType.swift`, keyed on `KnownBundleId` and window level, tested against `axDumps` by `Sources/AppBundleTests/AxUiElementWindowTypeTest.swift`) gives popup → popup container, dialog → floating, window → tiling, inserted after `workspace.mostRecentWindowRecursive` in its nearest alive tiling parent, or appended to the root.

### Workspaces, monitors, visible workspace

- `Workspace.get(byName:)` creates on miss. A new workspace is bound to the main monitor's container, then rebound to its force-assigned monitor if it has one. `garbageCollectUnusedWorkspaces` keeps persistent, non-empty, visible and focused workspaces in the name map.
- Monitors are keyed by `rect.topLeftCorner`. A lookup miss in `toMonitorOrRearrangeMonitors()` runs `rearrangeMonitors()`. It pairs old and new monitors that are each other's nearest top-left point and keeps those `Monitor` objects, along with their workspaces. Workspaces of surplus old monitors move to the main monitor. Leftover old `Monitor` objects take leftover infos in order of distance from the origin. `gcMonitors()` runs it when the screen count changes.
- The visible workspace is a name, `WorkspacesContainer.visibleWorkspaceNameOrStale`. `isVisible` compares names. `setVisibleWorkspace` first binds the workspace into that monitor's container, which moves it off another monitor, and refuses if it is force-assigned elsewhere. `getVisibleWorkspaceOrCreate` falls back to `getStubWorkspace`, which tries, in order: the previous visible workspace if it's free, the container's MRU workspace, and the first numeric name that is empty, invisible, not persistent and not force-assigned. It creates workspaces as it probes.
- `MonitorInfo` (`Sources/AppBundle/model/MonitorInfo.swift`) uses top-left-origin, y-down coordinates (flipped `NSScreen.frame`). `globalUnsortedMonitorInfos` re-reads `NSScreen.screens` on every access and isn't cached. `globalSortedMonitorInfos` sorts by minX, then minY, and gives the 1-based monitor IDs.

### MRU

Each node owns a `MruStack<TreeNode>` (`Sources/AppBundle/util/MruStack.swift`): a singly linked list whose push and remove are O(children). `markAsMostRecentChild()` raises the node in its parent and recurses to the root. `mostRecentChild` falls back to `children.last`. MRU drives: the focus target when a workspace is focused (`toLiveFocus` uses `mostRecentWindowRecursive`), where new windows go, accordion padding and hit-testing (both use the MRU inhabited child), which window is fullscreen-eligible, stub workspace choice, and focus-follows-mouse's floating hit order. `setFocus` (`Sources/AppBundle/focus.swift`) raises the new focused window, and the old one when the workspace changes.

### Window IDs

`OpaqueWindowId` (`Sources/Common/model/OpaqueWindowId.swift`) is AeroSpace's own UInt64 counter, which is what `--window-id` and `AEROSPACE_WINDOW_ID` carry. Each `MacApp` maps it to the native `CGWindowID` with a `BiDictionary` that is never pruned, so a window that disappears (screen lock) comes back with the same opaque ID. The native-tab heuristic re-points an opaque ID at a new native id when, within one app, exactly one window stops being alive and exactly one becomes alive between refreshes. That keeps the tree slot. `Window.get(byId:)` reads `MacWindow.allWindowsMap`. In unit tests it does a tree scan instead.

### Closed-windows cache (`Sources/AppBundle/tree/frozen/`)

Per the code's comments, a locked screen makes AX report every window as gone. When a window is GC'd, `cacheClosedWindowIfNeeded` snapshots the whole world (all monitors, workspaces, tiling trees with weights, and floating, fullscreen and hidden-app windows), unless every current window id is already in the snapshot. When a window whose id is in the snapshot is re-detected, `restoreClosedWindowsCacheIfNeeded` rebuilds every workspace's tiling tree from the snapshot and re-tiles orphans. Every command with `shouldResetClosedWindowsCache` and every mouse move or resize clears the cache, because a stale snapshot would undo the user's change.

### JSON models

`Json` (`Sources/AppBundle/model/Json.swift`) is an unordered DTO for AX dumps (`debug-windows`) and window-level parsing. `OrderedJson` is the TOML parse tree for config ([config.md](config.md)). `list-*` output doesn't use either. It's built from format variables in `Sources/AppBundle/command/formatToJson.swift` ([commands.md](commands.md)). `ServerEvent` is the `subscribe` payload ([shell-and-callbacks.md](shell-and-callbacks.md), [client-server.md](client-server.md)).

### Why the immutable rewrite (upstream 1215 and 1216) is hard here

Upstream's roadmap ties "windows may randomly jump to the focused workspace" (1216) to replacing this structure. The code shows why the current shape resists it and where that symptom can come from:

- Three structures per edge must stay consistent: the parent's `_children`, the child's weak `_parent`, and the parent's `_mruChildren`. MRU raises propagate to the root on every bind.
- Node identity is referenced from global side tables: `allWindowsMap`, `workspaceNameToWorkspace`, `pointToMonitor`, `MacApp.allAppsMap` (with a todo about folding it into 1215), the two global containers, `currentlyManipulatedWithMouseWindowId`, per-node `userData`, and the closed-windows snapshot. Focus avoids holding nodes by storing IDs and names (`FrozenFocus`), and re-resolves them on every read.
- Reads mutate. `rootTilingContainer`, `floatingWindowsContainer`, `macOsNativeFullscreenWindowsContainer`, `macOsNativeHiddenAppsWindowsContainer` and `getWorkspacesContainerOrCreate()` create and bind a node on first access, which raises MRU up to the monitor. `Workspace.get(byName:)` creates workspaces.
- Layout writes back into the model: weights (`layoutTiles`), `lastAppliedLayout*Rect`, and resetting `isFullscreen`.
- Mutations interleave with `await`s on the main actor. `unbindAndGetBindingDataForNewWindow` is documented as leaving the window unbound, refresh sessions are cancelled without being awaited (so two can interleave at suspension points), and `isBound` exists only because callers can observe unbound nodes ("todo drop, once 1215 is fixed").
- The paths that land a window on `globalFocus.workspace`: `MacWindow.getOrRegister` binds every non-popup window that isn't in `allWindowsMap` to the focused workspace (outside startup). So does any window that drops out of one refresh's alive set and comes back once the closed-windows cache has been reset. The same goes for windows leaving the minimized container (`normalizeLayoutReason` passes `globalFocus.workspace`) and popups promoted to windows (`validateStillPopups`).

## Rules worth keeping

- **Always go through `bind`.** It keeps children, parent and MRU in sync and validates the relation. Don't touch `_children` or `_parent`.
- **Hold a strong reference before unbinding a subtree** that you plan to reattach or read. Otherwise it is freed and the windows' `parent` turns `nil`.
- **Tombstones keep their slot.** Iterate `inhabitedChildren` for anything visual or geometric, and `children` for indices you pass to `bind`. `ownIndex(in: .all)` and `ownIndex(in: .inhabitedOnly)` differ.
- **Never bind into a non-alive container.** Debug builds die. Use `nearestAliveTilingParent()` to find a target.
- **Weights are pixels after the first layout.** If you introduce one in another unit, the next `layoutTiles` pass will rescale it silently. `setWeight` dies outside a matching-orientation `tiles` parent.
- **Container `lifeStatus` goes stale until the next `normalizeContainers()`.** Code that runs between window GC and the next normalization, including the layout pass of the same complete refresh, sees an emptied container as `.alive`.
- **Lazy getters are writes.** Reading `workspace.floatingWindowsContainer` or `rootTilingContainer` can add a node and reorder MRU up to the monitor, which changes later `mostRecentChild` answers (stub workspace choice, for one).
- **Workspace GC only drops the name-map entry.** `garbageCollectUnusedWorkspaces` never unbinds the `Workspace` node, so it stays in its `WorkspacesContainer.children` and MRU. A later `Workspace.get(byName:)` with the same name creates a second object. Code that walks container children (`FrozenMonitor.init`, `getVisibleWorkspaceOrCreate`'s first-match-by-name, `getStubWorkspace`'s MRU pick) can reach the old one, and `Workspace.==` dies if the two are ever compared. I haven't traced whether this is reachable in practice.
- **Unit tests run with both normalizations off** (`Sources/AppBundleTests/testUtil.swift`). `TestWindow` (`Sources/AppBundleTests/tree/TestWindow.swift`) doesn't implement `setAxFrame` or `isHiddenInCorner`, so layout isn't covered by tests.
