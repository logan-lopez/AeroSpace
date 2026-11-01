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
  /bin/bash is 3.2. On this machine it's zerobrew's, in `/opt/zerobrew/bin`, which sits after
  `/bin` on `PATH`: prefix the command with `PATH=/opt/zerobrew/bin:$HOME/.swiftly/bin:$PATH`.
- **swiftly**, which supplies the Swift toolchain pinned in `.swift-version`. There's no fallback
  to Xcode's `swift`. Installed from zerobrew; `swiftly init --no-modify-profile` and
  `swiftly install` in the repo are done (2026-11-01).

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
  Accessibility permission on behalf of the app at the top of the process chain that started it:
  kitty from a kitty shell, but `inn Stories.app` for a session running under it. On macOS 27
  the list is under Device Control and Data Access.
- **Window placement starts over.** The debug server doesn't know where the installed AeroSpace
  had your windows. Those it had hidden come back first, and the debug server puts each one on
  the visible workspace of the monitor it's on, so a window you kept on workspace 4 shows up on
  1. Move it back with the `.debug` CLI if a test depends on where it is.

`./build-debug.sh` alone builds into `.debug` without starting anything. Don't pass it
`-c release`: a release build takes the installed app's id and socket (`bobko.aerospace`) and
doesn't switch the installed one off, so the two would share a socket. When you're timing
something, build once and run the `aerospace` in `.debug` directly: `run-cli.sh` rebuilds on every call.
For numbers that matter, profile the release build, since debug builds are unoptimized.

## Installing a release build in place of the cask

`./install-from-sources.sh` builds a release `AeroSpace.app` and installs it as the
`aerospace-dev` cask. It **uninstalls the `aerospace` cask first**, so your Homebrew install is
gone until you reinstall it (brew install --cask nikitabobko/tap/aerospace).

It signs with a certificate named `aerospace-codesign-certificate` by default, which this machine
doesn't have. Sign with your Developer ID instead: build first, then install without rebuilding.

```sh
PATH=/opt/zerobrew/opt/ruby@3.4/bin:/opt/zerobrew/bin:$HOME/.swiftly/bin:$PATH
./build-release.sh --codesign-identity "Developer ID Application: Logan Lopez (CC63JS5AYR)"
./install-from-sources.sh --dont-rebuild
```

- **Ruby 3, not 4.** The docs Gemfile pins `~> 3.0`. zerobrew's `ruby` is 4, so the build uses
  `ruby@3.4`, which is keg-only, hence its bin first on `PATH`. fish comes from zerobrew too.
- **A clean working tree.** Commit first: the build fails on any uncommitted or untracked file.
  Building from a branch's worktree keeps `main`'s work out of the way.
- **The old server keeps running.** Uninstalling the cask doesn't quit it. Quit it from its menu
  (a normal quit puts hidden windows back), then open the new `/Applications/AeroSpace.app` and
  grant it Accessibility again: a new signature counts as a new app.
- The CLI and server versions read `0.0.0-SNAPSHOT <commit>`.

## What doesn't work from the fork

- Publishing a release (`script/publish-release.sh`) is upstream's maintainer flow and pushes to
  nikitabobko's repos.
- `./test.sh` fails on an uncommitted tree for the same reason as the release build. Run
  `./swift-test.sh` for the tests alone.
