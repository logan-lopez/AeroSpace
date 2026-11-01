---
sources: ["Package.swift", "Package.resolved", ".swift-version", "generate.sh", "xcode/", "build-debug.sh", "run-debug.sh", "run-cli.sh", "build-release.sh", "build-docs.sh", "build-shell-completion.sh", "install-from-sources.sh", "test.sh", "swift-test.sh", "lint.sh", "format.sh", "makefile", "script/", ".github/workflows/", ".github/gh-actions-runner-xcode-select.sh", ".swiftlint.yml", ".swiftformat"]
description: "How AeroSpace is built, tested, linted, generated and packaged (SPM, XcodeGen, the shell entry points, CI), for sessions touching build scripts or trying to get a local debug or release build running."
---
# Build and release

A set of bash entry-point scripts at the repo root drive everything: SPM builds the CLI, the
debug app and the tests; XcodeGen + `xcodebuild` builds only the release `AeroSpace.app`. CI and
every local build go through the same scripts.

**History:** upstream's `git log` for these paths; `dev-docs/development.md` and
`dev-docs/architecture.md` (upstream, stale; e.g. they mention `swiftformat.sh`, which is now
`format.sh`)

- `Package.swift`: all targets and pinned dependencies (exact versions; `Package.resolved` committed).
- `generate.sh`: toolchain pins and every generated file.
- `xcode/project.yml`: XcodeGen spec for the app bundle; `xcode/AeroSpace.xcodeproj` is its committed output.
- `script/setup.sh`: sourced by the other scripts; strict mode, bash 5 check, PATH sandbox, `xcodebuild-pretty`.
- `script/install-dep.sh`: lazily downloads pinned tools into `.deps`.
- `build-debug.sh`, `run-debug.sh`, `run-cli.sh`: SPM debug build and run.
- `test.sh`, `swift-test.sh`, `lint.sh`, `format.sh`, `makefile`: checks (`makefile` only wraps the scripts for vim's `:make`).
- `build-release.sh`, `script/validate-release-binaries.sh`, `script/build-brew-cask.sh`, `install-from-sources.sh`, `script/publish-release.sh`: release.
- `build-docs.sh`, `build-shell-completion.sh`: site, man pages, completions.
- `script/check-uncommitted-files.sh`, `script/clean-project.sh`, `script/clean-xcode.sh`, `script/reset-accessibility-permission-for-debug.sh`: housekeeping.
- `.github/workflows/build.yml`, `.github/workflows/queue.yml`: CI.

## How it works

### Script environment (`script/setup.sh`)

Every script cds to the repo root and sources `script/setup.sh`
(`script/reset-accessibility-permission-for-debug.sh` excepted). Setup:

- `set -euo pipefail`; `set -x` when `AEROSPACE_VERBOSE_BUILD` is non-empty (CI sets it).
- Requires bash 5 (`BASH_VERSION` must start with `5.`). Scripts use an `env bash` shebang, so a
  Homebrew bash must be first on `PATH`; macOS's /bin/bash 3.2 fails the check.
- On the outermost script only (`NUKE_PATH` unset) it rebuilds .deps/bin with shims for tools
  found on the caller's `PATH` (bash, fish, rustc, cargo, brew, bundle(r), xcbeautify, git,
  swiftly) and a `swift` shim that execs `swiftly run swift`, then sets
  PATH to .deps/bin:/bin:/usr/bin. Anything else from Homebrew is invisible to nested scripts.
  `swiftly` is mandatory; there is no fallback to Xcode's `swift`.
- `xcodebuild-pretty <log> <args>` tees `xcodebuild` output to a log and pipes through
  `xcbeautify --quiet` when available.

`script/install-dep.sh` (flags `--swiftlint`, `--swiftformat`, `--xcodegen`, `--periphery`,
`--complgen`, `--bundler`, `--all`) downloads pinned release zips (verified by sha256) into a per-tool directory under .deps, or `cargo install`s complgen
into .deps/cargo-root, or runs `bundler install`, and drops a marker keyed on the version so later runs skip it.

### Toolchain pins and `generate.sh`

`generate.sh` holds the version constants and rewrites files from them:

- `SWIFT_TOOLCHAIN_VERSION` (6.4.2) is written to `.swift-version`, which swiftly reads. Edit the
  constant, not the file.
- `SWIFT_PACKAGE_MANAGER_MANIFEST_FORMAT` (6.2) is sed'ed into the `swift-tools-version` line of
  `Package.swift`; it's capped by the SwiftPM built into Xcode, which `xcodebuild` uses to resolve
  the package regardless of toolchain.
- `MACOS_MIN_DEPLOYMENT_TARGET` (13) is sed'ed into `platforms:` (the line tagged
  `#MACOS_MIN_DEPLOYMENT_TARGET`) and exported to XcodeGen.
- `SWIFT_LANGAUGE_VERSION` (6) and the codesign identity are exported as `XCODEGEN_*` env vars
  that `xcode/project.yml` interpolates.

Generated sources, all committed:

- `Sources/Common/cmdHelpGenerated.swift` (via `script/generate-cmd-help.sh`): one
  `<cmd>_help_generated` string per command page (aerospace-<cmd>.adoc under docs), cut from its `tag::synopsis` block.
  These are the usage texts the `Common` parsers print. Skippable with `--ignore-cmd-help`
  (the script notes it costs about 300 ms).
- `Sources/Cli/subcommandDescriptionsGenerated.swift`: the `:manpurpose:` line of each adoc
  (exec-and-forget's excepted), for `aerospace --help`.
- `Sources/Common/versionGenerated.swift`: `aeroSpaceAppVersion`, `0.0.0-SNAPSHOT` unless `--build-version`.
- `Sources/Common/gitHashGenerated.swift`: `gitHash`/`gitShortHash`, `SNAPSHOT` unless `--generate-git-hash`.
- `xcode/AeroSpace.xcodeproj` (skippable with `--ignore-xcodeproj`): runs the pinned XcodeGen
  inside `xcode/`, with `TOOLCHAINS` set to the swiftly toolchain's bundle id so `xcodebuild`
  compiles with the same Swift as SPM.

### SPM targets and settings (`Package.swift`)

Products: `aerospace` (target `Cli`), `AeroSpaceApp` (debug only, per the manifest comment), and
the `AppBundle` library (exposed for Xcode). Dependencies, all `exact:`: swift-collections
(OrderedCollections, BasicContainers via the `UnstableHashedContainers` trait), TOMLDecoder,
HotKey, ISSoundAdditions, swift-syntax (for `Sources/Macros`). The Swift targets get
`NonisolatedNonsendingByDefault` and `strictMemorySafety()` (hence the `unsafe` markers across the
code); `Macros` and `PrivateApi` don't.

### Debug build and run

- `build-debug.sh [swift build args]`: `generate.sh --ignore-xcodeproj --ignore-cmd-help`, then
  `swift build --build-tests`, then copies `aerospace` and `AeroSpaceApp` from SPM's bin path into
  a fresh `.debug`. Both are DEBUG builds: the app id is `bobko.aerospace.debug`, so they use the
  debug socket (see client-server.md). The app is a bare executable, not a bundle: it finds
  `default-config.toml` by walking up from its compile-time `#filePath` to the repo's `.git`
  (`getDefaultConfigUrlFromProject` in `Sources/AppBundle/config/Config.swift`), so it only runs
  from a machine with this checkout. No codesign step runs on it; `dev-docs/development.md` says a debug build run from the
  terminal needs no certificate, and that Xcode runs should use the Terminal console so the
  Accessibility prompt goes to Terminal instead of recurring on every rebuild.
- `run-debug.sh [server args]`: builds, then runs `.debug`'s `AeroSpaceApp` in the foreground. At
  startup it sends `enable off` to a running release AeroSpace and `enable on` on exit.
  Server flags: `--config-path <path>`, `--read-only`, `-v`, `-h` (`initServerArgs` in
  `Sources/AppBundle/initAppBundle.swift`).
- `run-cli.sh <args>`: runs `build-debug.sh` (quietly, re-running loudly on failure) and then the
  debug `aerospace` with the args. That's a full generate + incremental build per invocation.
- Tests: `swift-test.sh` runs `swift test` and filters passing-test noise. XCTest, target
  `Sources/AppBundleTests`.

### Checks

- `test.sh`, the full gate, in order: `build-debug.sh -Xswiftc -warnings-as-errors`;
  `swift-test.sh`; smoke-runs the debug CLI with `-h`, `--help`, `-v`, `--version` (the version
  lines must contain `0.0.0-SNAPSHOT SNAPSHOT`; no server needed); `lint.sh`; full `generate.sh`;
  `script/check-uncommitted-files.sh`.
- `lint.sh`: runs `format.sh` (rewrites files in place with the pinned SwiftFormat, rules in
  `.swiftformat`); fails on any `Task.init`/`Task {`/`Task(` in `Sources` (use
  `Task.startUnstructured` from `Sources/Common/util/TaskEx.swift`); SwiftLint with the
  `only_rules` list in `.swiftlint.yml`; then Periphery (nikitabobko's fork, arm64 only, skipped on
  x86_64) in `--strict` mode, so unused code fails the lint.
- `script/check-uncommitted-files.sh` fails if `git status --porcelain` prints anything, untracked
  files included.

### Release build (`build-release.sh [--build-version V] [--codesign-identity ID]`)

1. `build-docs.sh --release` (asciidoctor via bundler into `.site` and `.man`) and
   `build-shell-completion.sh` (complgen from `grammar/commands-bnf-grammar.txt` into
   .shell-completion/{zsh,fish,bash}, then sources each with its shell as a syntax check, so
   fish is required).
2. `generate.sh`, `script/check-uncommitted-files.sh` (the tree must be clean and generated files
   current), then `generate.sh --build-version V --codesign-identity ID --generate-git-hash`.
3. CLI: `swift build -c release --arch arm64 --arch x86_64 --product aerospace -Xswiftc -warnings-as-errors`.
4. App: in `xcode/`, `xcodebuild clean build -scheme AeroSpace -configuration Release` into
   derived data at xcode/.xcode-build, log at .release/xcodebuild.log. Release config sets
   product `AeroSpace`, bundle id `bobko.aerospace`, warnings as errors; every config sets
   `LSUIElement=YES` and app sandbox off (the AX API doesn't work sandboxed). It's a clean build every time.
5. `git checkout .` reverts the version/hash/xcodeproj edits from step 2.
6. Copies `AeroSpace.app` and `aerospace` into `.release`, strips non-portable rpaths from the CLI
   (anything not starting with `@` and not the system Swift dylib directory), and `codesign -s ID` the CLI (Xcode
   signs the app with `CODE_SIGN_IDENTITY` from the project).
7. `script/validate-release-binaries.sh`: exact `.app` file layout; both binaries universal
   (x86_64 + arm64); exact rpath lists; exact linked-dylib lists (anything in the system Swift dylib directory
   allowed, `libswiftCompatibilitySpan` weak or strong); CLI links no `@rpath` dylibs; `codesign -v`
   both; both contain `git rev-parse HEAD`. A new framework import or dependency that adds a dylib
   fails here until the expected list is updated.
8. Packs .release/AeroSpace-vV/ (app, bin/aerospace, manpage, legal, shell-completion) and its
   `.zip`, then `script/build-brew-cask.sh` writes `aerospace.rb` and `aerospace-dev.rb` casks
   into `.release` pointing at the local zip (`version :latest` for SNAPSHOT builds).

The codesign identity defaults to `aerospace-codesign-certificate`, a self-signed code-signing
certificate you create in Keychain Access (steps in `dev-docs/development.md`). CI passes `-`
(ad-hoc). Debug builds need no certificate.

`install-from-sources.sh [--dont-rebuild]`: runs `build-release.sh`, then uninstalls any
`aerospace` and previously installed `aerospace-dev` casks and installs .release/aerospace-dev.rb with
`brew install-path` (the brew-install-path formula from nikitabobko's tap, installed if missing), using a
throwaway `HOMEBREW_CACHE` in /tmp.

`script/publish-release.sh` is upstream's maintainer flow (runs `test.sh` and
`build-release.sh`, pushes a tag to nikitabobko/AeroSpace, updates the cask and site repos); it's
not usable from a fork as is.

### Build outputs

All are dot-dirs at the root, ignored by the root dot-file rule in `.gitignore`: `.debug` (debug CLI and
app), `.release` (app, CLI, zip, casks, xcodebuild log), `.site` (HTML docs), `.man` (man pages),
`.shell-completion`, `.deps` (tool shims and downloads), `.build` (SPM). Xcode derived data goes
to xcode/.xcode-build, also ignored.

### CI (`.github/workflows/`)

- `build.yml`: on push to `main` and to branches prefixed rr ("remote run"), PRs to `main`, nightly cron,
  `workflow_call` and manual dispatch. Matrix `macos-15`, `macos-26`, `xcode-27` for two jobs:
  `build-debug` (`build-debug.sh`, `test.sh`) and `build-release` (`build-release.sh
  --codesign-identity -`, then `install-from-sources.sh --dont-rebuild`, then dumps the xcodebuild
  log). Both install bash and swiftly from Homebrew and `swiftly install` the pinned toolchain;
  `.github/gh-actions-runner-xcode-select.sh` selects Xcode 26 on the macOS 15/26 runners.
- `queue.yml`: upstream's merge queue. Push to a branch prefixed q runs `build.yml`, and on success a job
  pushes that commit to `main` (fast-forward only; full-history checkout so the push works).
- `close-third-party-issues.yml`, `label-incoming-prs.yml`: issue/PR housekeeping, no build.

## Rules worth keeping

- Never hand-edit `*Generated.swift`, `.swift-version`, the tools-version/platforms lines of
  `Package.swift`, or `xcode/AeroSpace.xcodeproj`. `test.sh` reruns `generate.sh` and fails on any
  diff, and `build-release.sh` reverts them with `git checkout .`.
- Changing a command's synopsis in its aerospace-<cmd>.adoc page under docs changes `--help` output and the
  committed `Sources/Common/cmdHelpGenerated.swift`; run the full `generate.sh` (`build-debug.sh`
  skips cmd help) and commit both.
- `test.sh` and `build-release.sh` require a clean working tree, untracked files included.
  Commit or stash first, including in-progress docs.
- `build-release.sh` runs `git checkout .` midway; don't edit tracked files while it runs.
- `script/clean-project.sh` runs `script/clean-xcode.sh` (which refuses a dirty tree) and then
  `git clean -ffxd`, which deletes every ignored file, local .claude state included. `script/clean-xcode.sh` also deletes
  and regenerates `xcode/AeroSpace.xcodeproj`.
- `install-from-sources.sh` uninstalls the Homebrew `aerospace` cask before installing
  `aerospace-dev`. Use it only when you want the source build to replace the installed app.
- `lint.sh` (and so `test.sh`) reformats sources in place before checking. Expect diffs after
  running it on unformatted code.
- `Task.init` and `Task { }` are banned by `lint.sh`; use `Task.startUnstructured`.
- Adding a dependency or system framework requires updating the expected dylib lists in
  `script/validate-release-binaries.sh`, or the release build fails at validation.
- The scripts need Homebrew bash 5 and swiftly on `PATH` at launch; once `script/setup.sh` runs,
  other Homebrew tools aren't visible unless shimmed in it.
- For performance measurement, build with `build-debug.sh` once and run the binaries in `.debug`
  directly; `run-cli.sh` rebuilds on every call. `.debug` holds SPM debug-configuration
  builds; the manifest says not to ship SPM's `AeroSpaceApp`, and the shipped server comes only
  from the Xcode Release build in `build-release.sh`. Profile against that when the numbers matter.
