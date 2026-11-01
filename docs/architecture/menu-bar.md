---
sources: ["Sources/AppBundle/ui/", "Sources/AeroSpaceApp/AeroSpaceApp.swift"]
description: "The menu bar extra, its TrayMenuModel and how often it is rebuilt, plus the HUD panels and config-diagnostics window, for sessions touching AeroSpace's own UI."
---
# Menu bar and HUD

AeroSpace's own UI: the SwiftUI `MenuBarExtra` driven by `TrayMenuModel`, two floating HUD panels (secure
input, volume) and the config diagnostics window. Nothing depends on it, except that
`TrayMenuModel.shared.isEnabled` doubles as the global "AeroSpace is enabled" switch every observer and
session checks ([windows-and-focus.md](windows-and-focus.md)).

**History:** upstream's `git log` for these paths; `dev-docs/architecture.md` (upstream, stale)

Where the code is:

- `Sources/AeroSpaceApp/AeroSpaceApp.swift`: the `@main` `App`. Holds `TrayMenuModel.shared` and
  `MessageModel.shared`, declares both scenes, opens the message window when a message appears, and calls
  `initAppBundle()` from `init`.
- `Sources/AppBundle/ui/TrayMenuModel.swift`: the `ObservableObject` and `updateTrayText()`, which rebuilds it;
  `Sources/AppBundle/ui/MenuBar.swift`: menu contents, label switch, shared open/reload config buttons.
- `Sources/AppBundle/ui/MenuBarLabel.swift`: the label's five styles; `Sources/AppBundle/ui/ExperimentalUISettings.swift`:
  the style setting and submenu; `Sources/AppBundle/ui/AppearanceTheme.swift`: light/dark from `effectiveAppearance`.
- `Sources/AppBundle/ui/NSPanelHud.swift`: base panel; `Sources/AppBundle/ui/SecureInputView.swift`,
  `Sources/AppBundle/ui/VolumeView.swift`: the HUDs; `Sources/AppBundle/ui/MessageView.swift`: the
  diagnostics window and `MessageModel`.

## How it works

### TrayMenuModel and who writes it

`@Published`: `trayText`, `trayItems`, `workspaces`, `isEnabled`, `experimentalUISettings`,
`sponsorshipMessage`, `lastReloadConfigContainedWarnings`, `axPermissionStatus`.

- `updateTrayText()` writes `trayText`, `workspaces` and `trayItems`. It's called from both
  `runHeavyCompleteRefreshSession` and `runLightSession` in `Sources/AppBundle/layout/refresh.swift`, so it runs
  on **every refresh session**. A command's light session ends by scheduling a heavy one, so it normally runs
  twice per command, plus once per AX/NSWorkspace-triggered heavy session that isn't cancelled before reaching
  it. All three properties are assigned every time with no equality check, and `@Published` emits on every
  assignment (Combine behavior), so every call publishes even when nothing changed. It walks `allLeafWindowsRecursive` of every workspace twice (app names, fullscreen flag) and
  of each visible workspace twice more.
- Other writers: `isEnabled` by `EnableCommand`, `lastReloadConfigContainedWarnings` by `reloadConfig_nonCancellable`,
  `axPermissionStatus` by the startup permission wait and the menu's permission button (re-prompts),
  `experimentalUISettings` by the style submenu, `sponsorshipMessage` by the sponsor button.

`trayText` is `(M) ` for a non-main mode, then each monitor's visible workspace (sorted monitors) joined by
` │ `, `[bracketed]` if it holds a fullscreen window, `*`-prefixed when focused and there are several monitors.
`workspaces` has one `WorkspaceViewModel` per workspace: name, suffix (sorted app names truncated to 25 chars,
or the monitor name for a visible empty one) and flags; it feeds the "Workspaces:" list and the i3 styles.
`trayItems` is one item per monitor's visible workspace, mode item first; `TrayItem.systemImageName` maps names
`0`–`50` and single letters `A`–`Z` to SF Symbols (`n.square`, `n.square.fill` when active, `n.circle` for a
mode), anything else renders as text.

### Menu and label

`menuBar(viewModel:)`: version and copy (⌘C). With permission granted: "Config contains warnings..." while
enabled and the last reload warned (reloads with warnings as errors, which opens the diagnostics window); the
workspace list while enabled (each item focuses the workspace); sponsor; Enable/Disable (⌘E, `EnableCommand`
under `.forceRun` so it works while disabled); the style submenu; open config (⌘,); reload config (⌘R, while
enabled). Quit (⌘Q) runs the termination handler then `terminateApp()`. Every action that touches window state, except Quit, runs in
`runLightSession`, like a CLI command. The label is `MenuBarLabel` when granted and enabled,
`pause.circle.fill` when disabled, a warning triangle without permission.

`MenuBarLabel.body`, on macOS 14+, renders `menuBarContent` to a `CGImage` with `ImageRenderer` on each
evaluation (scale 2; scale 1 is blurry), falling back to `Text(trayText)`; older systems always get the text
(upstream issue 1122). It observes the model as an `@EnvironmentObject`. Styles: `monospacedText` and
`systemText` (render `trayText`), `squares` (`trayItems`), `i3` (squares plus non-empty invisible workspaces,
dimmed), `i3Ordered` (every non-empty or visible workspace in order, invisible at half opacity). Emoji names
render as text; fullscreen workspaces get a dashed outline. The style submenu builds one `MenuBarLabel` per
style as a preview. `ExperimentalUISettings.displayStyle` reads UserDefaults key `displayStyle` on every access
(default `monospacedText`) and writes plus `synchronize()`s on set.

### HUD panels

Both subclass `NSPanelHud`: non-activating, borderless, `.floating`, on all Spaces including fullscreen ones.

- `SecureInputPanel.refresh()` also runs on every refresh session, right after `updateTrayText()`. It shows a
  50×50 lock icon near the main monitor's bottom-right corner when a mode with bindings is active, AeroSpace is
  enabled and `IsSecureEventInputEnabled()` is true (hotkeys can't fire under Secure Input), and closes it
  otherwise; if already visible it returns early. Tapping toggles an explanation.
- `VolumePanel.update(with:)`, from the `volume` command, shows a level bar at the main monitor's right edge and
  closes it after a 2-second `Timer`, restarted on each update.

### Config diagnostics window

`getMessageWindow` declares a `SwiftUI.Window` (`messageWindowId`) for `MessageModel.shared.message`.
`reloadConfig_nonCancellable` (behind `ReloadConfigCommand`, startup, the menu and the config watcher) sets it on parse errors, or on warnings when warnings are treated as errors, and clears it
otherwise (skipped under `--no-gui`); plain warnings only surface as the menu item. On appear the window
switches the app to `.accessory` activation policy (otherwise it can't take keyboard focus), goes `.floating`
and loses its minimize button. Enter in the read-only text editor, Close, or the close button clears the
message.

## Rules worth keeping

- **`updateTrayText()` and `SecureInputPanel.refresh()` are on the hot path.** They run on the main actor on
  every session. Anything added there (tree walks, AX calls, heavier label rendering) is paid per event, and
  every write invalidates the observing label, which SwiftUI then re-renders through `ImageRenderer`.
- **`isEnabled` is not just UI state.** Observers and sessions return early when it's false. Flipping it outside
  `EnableCommand` skips that command's floating-size capture and mode switch.
- **UI actions go through `runLightSession` with a `RunSessionGuard`**, so focus sync, layout and the follow-up
  refresh behave as for CLI commands. Only Enable uses `.forceRun`.
- **Keep the message window `.accessory`-activating and unminimizable.** Without the policy change it can't
  receive keyboard input; nothing unminimizes it on the next config error.
