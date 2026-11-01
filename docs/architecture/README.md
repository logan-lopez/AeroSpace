# Architecture

AeroSpace is two processes: `AeroSpace.app`, a long-running server that owns the window tree and
drives windows through the Accessibility (AX) API, and `aerospace`, a short-lived CLI client that
forwards one command per invocation over a Unix socket. Hotkeys, config callbacks and CLI
requests all run the same `Command` implementations inside the server.

**History:** upstream's `git log`; `dev-docs/architecture.md` (upstream, stale: it still names an
xcode-app-bundle-launcher directory and a root project.yml, neither of which exists now)

## Modules

All Swift code lives under `Sources/`, one directory per SPM target declared in `Package.swift`.

| Target | Kind | Role |
| --- | --- | --- |
| `Sources/AppBundle` | library | The server. Tree model, layout, commands, config, AX glue, menu bar UI, socket server. Exposed as a library product only so Xcode can wrap it in an app bundle. |
| `Sources/Cli` | executable `aerospace` | The client. Parses args locally, sends them over the socket, prints the answer, exits with the server's exit code. Depends only on `Common` and `Macros`. |
| `Sources/Common` | library | Code both sides need: every command's arg parser (`Sources/Common/cmdArgs/`), the socket wire types (`Sources/Common/model/clientServer.swift`) and framing (`Sources/Common/util/NWConnectionEx.swift`), generated help text and version, shared utils. Imports AppKit, so the CLI links AppKit too. |
| `Sources/AeroSpaceApp` | executable `AeroSpaceApp` | One file, `Sources/AeroSpaceApp/AeroSpaceApp.swift`: the SwiftUI `@main` that calls `initAppBundle()` and declares the menu bar scene. Compiled both by SPM (debug) and by the Xcode project (release). |
| `Sources/Macros` | macro plugin | `#myFileId` and file-path macros that expand to a `MyFileId` (file, line, column, function), used for `check`/`die` diagnostics. Built on swift-syntax. |
| `Sources/PrivateApi` | C target | Header exposing the private `_AXUIElementGetWindow`, which maps an AX element to its `CGWindowID`. |
| `Sources/AppBundleTests` | XCTest target | Unit tests against `AppBundle` (commands, config parsing, tree, shell, client-server JSON decoding). Run by `swift test`. |

Inside `Sources/AppBundle`, the directories map onto the other pages here:

- `Sources/AppBundle/command/`: `Command` protocol, `CmdEnv`/`CmdIo`, the args-to-command switch in `Sources/AppBundle/command/cmdManifest.swift`, one file per command in `Sources/AppBundle/command/impl/`. See commands.md.
- `Sources/AppBundle/config/`: TOML parsing, hotkey registration and modes, config file watcher. See config.md.
- `Sources/AppBundle/tree/`: `TreeNode`, `Workspace`, `TilingContainer`, `MacApp`/`MacWindow`, monitors. See tree-model.md.
- `Sources/AppBundle/layout/`: refresh sessions (`Sources/AppBundle/layout/refresh.swift`) and the recursive layout pass. See layout-and-refresh.md.
- `Sources/AppBundle/focus.swift`, `Sources/AppBundle/focusCache.swift`, `Sources/AppBundle/getNativeFocusedWindow.swift`, `Sources/AppBundle/GlobalObserver.swift`: focus model and NSWorkspace observation. See windows-and-focus.md.
- `Sources/AppBundle/mouse/`: move/resize with mouse, focus-follows-mouse. See mouse.md.
- `Sources/AppBundle/shell/`: the mini shell lexer/parser for command strings from config and `eval`. See shell-and-callbacks.md.
- `Sources/AppBundle/ui/`: SwiftUI menu bar, HUD panels. See menu-bar.md.
- `Sources/AppBundle/server.swift`, `Sources/AppBundle/subscriptions.swift`: socket server and `subscribe` streaming. See client-server.md.

## SPM vs the Xcode project

SPM (`Package.swift`) is the source of truth for every target, and it is all that debug builds,
tests and the CLI release build use. SPM can't produce a macOS `.app` bundle, so
`xcode/project.yml` (an XcodeGen spec) describes one application target, `AeroSpace`, whose
only sources are `Sources/AeroSpaceApp`, `resources` and `docs/config-examples/default-config.toml`,
and which pulls in the `AppBundle` library product through `xcode/aerospace-package-symlink`
(a symlink to the repo root). `generate.sh` runs XcodeGen to regenerate the committed
`xcode/AeroSpace.xcodeproj`; only `build-release.sh` builds through it. Details, including the
generated Swift files, are in build-and-release.md.

## Threading model

Everything that touches the tree, focus, config or UI is `@MainActor`: `Command.run`,
`runLightSession`, `runHeavyCompleteRefreshSession`, hotkey handlers. AX calls go through a
dedicated `Thread` per running app (`MacApp` starts one named `AxAppThread <app>` that spins a
`CFRunLoop`); the main actor submits work with `Thread.runInLoop` (`Sources/AppBundle/runLoop.swift`)
and awaits a continuation, so a slow or hung app stalls the awaiting refresh session rather than
blocking the main thread outright. The socket listener and per-connection reads/writes run on the
global dispatch queue; each request hops to the main actor to execute. `Package.swift` enables
`NonisolatedNonsendingByDefault`, so a nonisolated `async` function runs on its caller's actor:
read call sites, not just declarations, to know which thread code is on.

## Where to start: tracing a command end to end

Take `aerospace focus left`:

1. `Sources/Cli/_main.swift`: `parseCmdArgs` (from `Sources/Common/cmdArgs/parseCmdArgs.swift`)
   validates the args locally, then the client connects to the socket, handshakes and sends a
   `ClientRequest` with the raw args.
2. `Sources/AppBundle/server.swift`: `newConnection` decodes the request and calls `parseCommand`
   (`Sources/AppBundle/command/parseCommand.swift`), which re-parses with the same `Common`
   parser and maps the result to a `Command` via `toCommand()` in
   `Sources/AppBundle/command/cmdManifest.swift`.
3. `runLightSession` in `Sources/AppBundle/layout/refresh.swift` wraps execution: native focus
   lookup, model refresh, the command body, model refresh, `layoutWorkspaces`, focus sync to macOS,
   then schedules a cancellable full refresh.
4. The command body: `Sources/AppBundle/command/impl/FocusCommand.swift`, run through
   `Shell.cmd(self).run` (`Sources/AppBundle/command/Command.swift`).
5. The `ServerAnswer` goes back to the client, which prints stdout/stderr and exits with the code.

A hotkey enters at step 3 from `Sources/AppBundle/config/HotkeyBinding.swift`, skipping the socket.
For performance work, `runLightSession` and `runHeavyCompleteRefreshSession` are wrapped in
`OSSignposter` intervals (subsystem = the app id, category points of interest; `signposter` in
`Sources/AppBundle/util/appBundleUtil.swift`), so they show up in Instruments.

## Pages

<!-- Generated by docket areas; edit descriptions in the pages' frontmatter. -->

- [Build and release](build-and-release.md): How AeroSpace is built, tested, linted, generated and packaged (SPM, XcodeGen, the shell entry points, CI), for sessions touching build scripts or trying to get a local debug or release build running.
- [Client-server protocol](client-server.md): The aerospace CLI to AeroSpace.app socket protocol (handshake, framing, request/answer, subscribe streaming) and the client process, for sessions changing either end or chasing CLI latency.
- [Commands](commands.md): How commands are declared, parsed (on both client and server), targeted and run, plus the generated help, docs and shell-completion files that must stay in sync, for sessions adding or changing a command.
- [Config](config.md): Where the TOML config is found, how it is parsed into the Config struct and validated, how reload and auto-reload swap it in, and how modes and hotkeys, gaps, monitor assignment and on-window-detected are represented, for sessions adding or changing a config option.
- [Layout and refresh](layout-and-refresh.md): Refresh sessions (triggers, order of work, cancellation), macOS layout-reason normalization, frame computation (gaps, weights, accordion padding, hide-in-corner) and how frames reach windows, with per-session cost, for sessions chasing latency or changing layout.
- [Menu bar and HUD](menu-bar.md): The menu bar extra, its TrayMenuModel and how often it is rebuilt, plus the HUD panels and config-diagnostics window, for sessions touching AeroSpace's own UI.
- [Mouse](mouse.md): How mouse drags and resizes are detected through AX notifications, how they move windows and recompute tiling weights, and how focus-follows-mouse picks a window, for sessions changing mouse behaviour or its per-event cost.
- [Shell and callbacks](shell-and-callbacks.md): AeroSpace's mini shell (lexer, parser, &&/||/;/|, eval), exec-and-forget and exec-on-workspace-change process spawning, the AEROSPACE_* env vars, and where each config callback is dispatched and what it costs, for sessions touching command strings, callbacks or scripting performance.
- [Tree model](tree-model.md): The window tree (node types, bind/unbind, weights, orientation, normalization, tombstones, MRU, monitors and visible workspaces, window IDs) and its invariants, for sessions changing how nodes are stored, created or moved.
- [Windows and focus](windows-and-focus.md): The accessibility layer, thread-per-application model, AX and NSWorkspace observation, caches, focus reconciliation and startup, for sessions touching window observation, focus or performance.
