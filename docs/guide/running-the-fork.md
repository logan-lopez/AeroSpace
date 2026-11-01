---
covers: ["docs/architecture/build-and-release.md", "docs/architecture/client-server.md", "dev-docs/development.md"]
description: "Building the fork, running its debug build beside the installed AeroSpace, and installing a source build, for Logan trying a change on his own desktop."
---
# Running the fork

How to get the fork's code running on your machine: a debug build you start from the terminal
while the installed AeroSpace steps aside, or a release build installed in its place. How the
build works underneath is on [the build page](../architecture/build-and-release.md).

## Before the first build

The scripts need two things this machine doesn't have yet:

- **bash 5 first on `PATH`.** Every script runs `env bash` and refuses anything older, and macOS's
  /bin/bash is 3.2. `brew install bash`.
- **swiftly**, which supplies the Swift toolchain pinned in `.swift-version`. There's no fallback
  to Xcode's `swift`. `brew install swiftly`, then `swiftly init` and `swiftly install` in the repo.

Formatters, linters and XcodeGen download themselves on first use. The release build needs more,
because it also builds the man pages and shell completions: Xcode, fish, Rust (cargo) and Ruby
with bundler.

## The debug build, beside the installed app

`./run-debug.sh` builds and starts the debug server in the foreground of your terminal. While it
runs:

- **The installed AeroSpace steps aside.** The debug server sends it `enable off` at startup and
  `enable on` when you stop it with Ctrl-C, so your Homebrew AeroSpace stays installed and takes
  over again afterwards. Switched off, it drops its key bindings, so the debug server's take
  effect, and windows it had hidden on other workspaces come back. Stopping the debug server any
  other way than Ctrl-C (a `kill -9`, a crash) skips the `enable on`, and the installed AeroSpace
  stays switched off: run `aerospace enable on`, or pick Enable in its menu.
- **It reads your normal config,** ~/.aerospace.toml (or ~/.config/aerospace/aerospace.toml).
  `--config-path <file>` points it at another one, which is the way to try a config change
  without touching your dotfiles: pass it to `./run-debug.sh`.
- **It has its own socket.** The `aerospace` on your `PATH` is the installed one and talks to the
  installed server, which is switched off. To send the debug server a command, use
  the `aerospace` in `.debug` (or `./run-cli.sh` with the same args, which rebuilds first). Anything
  that calls plain `aerospace`, such as the scripts in ~/.config/aerospace or BetterTouchTool's Cmd-Tab,
  keeps talking to the installed server, not the debug one. Key bindings in the config run inside
  the debug server and work as usual.
- **Accessibility.** The debug server is a bare executable, not an app, so macOS asks for the
  Accessibility permission on behalf of the terminal that started it (kitty).

`./build-debug.sh` alone builds into `.debug` without starting anything. When you're timing
something, build once and run the `aerospace` in `.debug` directly: `run-cli.sh` rebuilds on every call.
For numbers that matter, profile the release build, since debug builds are unoptimized.

## Installing a release build in place of the cask

`./install-from-sources.sh` builds a release `AeroSpace.app` and installs it as the
`aerospace-dev` cask. It **uninstalls the `aerospace` cask first**, so your Homebrew install is
gone until you reinstall it (brew install --cask nikitabobko/tap/aerospace).

It signs with a self-signed certificate named `aerospace-codesign-certificate`, which you create
once in Keychain Access (steps in `dev-docs/development.md`). A release build also needs a clean
working tree: commit first, since it fails on any uncommitted or untracked file.

## What doesn't work from the fork

- Publishing a release (`script/publish-release.sh`) is upstream's maintainer flow and pushes to
  nikitabobko's repos.
- `./test.sh` fails on an uncommitted tree for the same reason as the release build. Run
  `./swift-test.sh` for the tests alone.
