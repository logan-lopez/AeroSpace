# AeroSpace (Logan's fork)

This is Logan's personal fork of [AeroSpace](https://github.com/nikitabobko/AeroSpace), an i3-like
tiling window manager for macOS written in Swift. `main` tracks upstream's `main` (remote
`upstream`) and adds this file and the docs under `docs/briefs/`, `docs/decisions/`,
`docs/architecture/` and `docs/guide/`. Upstream's own files (`README.md`, `dev-docs/`, the
asciidoc site in `docs/*.adoc`, `CONTRIBUTING.md`) are left as upstream has them. The fork is
mainly for digging into a performance issue, which may go upstream, so changes that might follow
upstream's `CONTRIBUTING.md` rules. Handoff briefs are in `docs/briefs/`. Start with `README.md`;
unscheduled ones are in `FUTURE.md`, and finished ones move to `archive/`.

How the code works is in `docs/architecture/`, one page per area (start with its `README.md`),
and the Areas table below says which page goes with which code. `docs/guide/` covers what's
specific to running the fork; AeroSpace's own user guide is upstream's `docs/guide.adoc` and
`docs/commands.adoc`. Update a guide page in the same brief that changes what it describes. Logan
keeps no Obsidian folder for this project.

## Git

- Upstream is `https://github.com/nikitabobko/AeroSpace` (remote `upstream`). Merge
  `upstream/main` into `main`; don't rebase `main`.
- Cut a branch meant as an upstream PR from `upstream/main`, never from `main`, which carries the
  fork's docs.
- Upstream's commit messages are short imperative subjects, often with a scope
  (`build-release.sh: ...`). Match them in anything that might go upstream.

## Commands

- `./build-debug.sh`: SPM debug build into `.debug/` (`aerospace` CLI and `AeroSpaceApp`).
- `./run-debug.sh`: build and run the debug server. `./run-cli.sh <args>` runs the debug CLI.
- `./swift-test.sh`: unit tests only (`Sources/AppBundleTests/`).
- `./test.sh`: the full check: build with warnings as errors, tests, `lint.sh`, `generate.sh`,
  then `script/check-uncommitted-files.sh`, which fails on any uncommitted change. Commit first,
  or run the steps by hand.
- `./format.sh` (swiftformat) and `./lint.sh` (format, swiftlint, periphery).
- `./generate.sh`: regenerates the Xcode project and the `*Generated.swift` files. Run it after
  adding a command or changing its args.

## Rules

- Never write `Task { }` or `Task.init`; use `Task.startUnstructured`. `lint.sh` greps for it.
- Don't edit upstream's `README.md`, `dev-docs/`, `docs/*.adoc` or `CONTRIBUTING.md` for the
  fork's own notes; they belong in the fork's docs paths, so upstream merges stay clean.

### Areas

`docs/architecture/` has one page per area, describing the code as it is now (start with [the
overview](docs/architecture/README.md)). Before changing code in an area, read its page. `docket
context <path>` lists the pages, decisions and open briefs that bind a file. When a change makes a
sentence on a page untrue, fix the page in the same commit. A new area gets a page, a row here and a
pointer in `.claude/rules/` (Claude Code loads the matching one by itself; this table is the same
map for every agent).

| Code | Read first |
| --- | --- |
| `Package.swift`, `Package.resolved`, `.swift-version`, `generate.sh`, `xcode/**`, `build-debug.sh`, `run-debug.sh`, `run-cli.sh`, `build-release.sh`, `build-docs.sh`, `build-shell-completion.sh`, `install-from-sources.sh`, `test.sh`, `swift-test.sh`, `lint.sh`, `format.sh`, `makefile`, `script/**`, `.github/workflows/**`, `.github/gh-actions-runner-xcode-select.sh`, `.swiftlint.yml`, `.swiftformat` | [Build and release](docs/architecture/build-and-release.md) |
| `Sources/Cli/**`, `Sources/AppBundle/server.swift`, `Sources/AppBundle/subscriptions.swift`, `Sources/AppBundle/model/ServerEvent.swift`, `Sources/Common/model/clientServer.swift`, `Sources/Common/util/NWConnectionEx.swift` | [Client-server protocol](docs/architecture/client-server.md) |
| `Sources/AppBundle/command/**`, `Sources/Common/cmdArgs/**`, `Sources/Common/cmdHelpGenerated.swift`, `grammar/**`, `docs/commands.adoc` | [Commands](docs/architecture/commands.md) |
| `Sources/AppBundle/config/**`, `docs/config-examples/**` | [Config](docs/architecture/config.md) |
| `Sources/AppBundle/layout/**`, `Sources/AppBundle/normalizeLayoutReason.swift` | [Layout and refresh](docs/architecture/layout-and-refresh.md) |
| `Sources/AppBundle/ui/**`, `Sources/AeroSpaceApp/AeroSpaceApp.swift` | [Menu bar and HUD](docs/architecture/menu-bar.md) |
| `Sources/AppBundle/mouse/**` | [Mouse](docs/architecture/mouse.md) |
| `Sources/AppBundle/shell/**`, `Sources/Common/model/AeroSpaceEnvVars.swift` | [Shell and callbacks](docs/architecture/shell-and-callbacks.md) |
| `Sources/AppBundle/tree/**`, `Sources/AppBundle/model/**`, `Sources/Common/model/OpaqueWindowId.swift` | [Tree model](docs/architecture/tree-model.md) |
| `Sources/AppBundle/focus.swift`, `Sources/AppBundle/focusCache.swift`, `Sources/AppBundle/getNativeFocusedWindow.swift`, `Sources/AppBundle/GlobalObserver.swift`, `Sources/AppBundle/runLoop.swift`, `Sources/AppBundle/windowLevelCache.swift`, `Sources/AppBundle/initAppBundle.swift`, `Sources/AppBundle/tree/MacApp.swift`, `Sources/AppBundle/util/accessibility.swift`, `Sources/AppBundle/util/AxSubscription.swift`, `Sources/AppBundle/util/ThreadGuardedValue.swift`, `Sources/AppBundle/util/AwaitableOneTimeBroadcastLatch.swift`, `Sources/AppBundle/util/CompletableFuture.swift`, `Sources/AppBundle/util/AxUiElementMock.swift`, `Sources/AppBundle/util/axTrustedCheckOptionPrompt.swift`, `Sources/AppBundle/util/dumpAxRecursive.swift`, `Sources/AppBundle/util/appBundleUtil.swift`, `Sources/Common/model/AxAppThreadToken.swift`, `Sources/PrivateApi/**` | [Windows and focus](docs/architecture/windows-and-focus.md) |
