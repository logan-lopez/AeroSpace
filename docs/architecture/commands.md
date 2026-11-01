---
sources: ["Sources/AppBundle/command/", "Sources/Common/cmdArgs/", "Sources/Common/cmdHelpGenerated.swift", "grammar/", "docs/commands.adoc"]
description: "How commands are declared, parsed (on both client and server), targeted and run, plus the generated help, docs and shell-completion files that must stay in sync, for sessions adding or changing a command."
---
# Commands

Every action AeroSpace takes on behalf of the user is a command: hotkeys, CLI requests, config
callbacks and `eval` all end up as a `Command` struct run on the main actor. The args half lives
in `Common` so the `aerospace` CLI and the server parse with identical code.

**History:** upstream's `git log` for these paths;
`dev-docs/architecture.md` (upstream, stale; its "Commands subsystem" section is a todo plus the
checklist updated below)

Args side, `Sources/Common/cmdArgs/` (compiled into both CLI and server):

- `Sources/Common/cmdArgs/cmdArgsManifest.swift`: `CmdKind` (every subcommand name) and `initSubcommands()`, the name to parser table, including deprecated aliases (`move-through`, `move-workspace-to-display`).
- `Sources/Common/cmdArgs/parseCmdArgs.swift`: `parseCmdArgs` entry point, the `CmdArgs` protocol, `CmdArgsCommonState`, `CmdParser`, `CmdStaticInfo`.
- `Sources/Common/cmdArgs/parseSpecificCmdArgs.swift`: the generic flag/positional loop shared by every command; `CmdParsingFailure`.
- `Sources/Common/cmdArgs/ArgParser.swift`, `Sources/Common/cmdArgs/SubArgParser.swift`, `Sources/Common/cmdArgs/ArgParserInput.swift`, `Sources/Common/cmdArgs/ParsedCliArgs.swift`: keypath-based arg parsers and their helpers (`trueBoolFlag`, `singleValueSubArgParser`, `windowIdSubArgParser`, `workspaceSubArgParser`, `newMandatoryPosArgParser`, `doubleDashArg`, `parseEnum`).
- `Sources/Common/cmdArgs/ParsedCmd.swift`: `ParsedCmd<T>` = `.cmd | .help | .failure`, with `map`/`flatMap`/`filter`/`filterNot`.
- `Sources/Common/cmdArgs/ExitCode.swift`: `BinaryExitCode`, `ConditionalExitCode`, `Int32ExitCode`, `IoSideEffect`.
- `Sources/Common/cmdArgs/subcommandParsers.swift`: the `subcommandParsers` global and `SubCommandParser`.
- `Sources/Common/cmdArgs/joinArgs.swift`: re-quotes args when printing a command back (`CmdArgs.description`).
- `Sources/Common/cmdArgs/impl/`: one `<Name>CmdArgs.swift` per command.

Run side, `Sources/AppBundle/command/` (server only):

- `Sources/AppBundle/command/Command.swift`: the `Command` protocol.
- `Sources/AppBundle/command/cmdManifest.swift`: `CmdArgs.toCommand()`, the exhaustive `CmdKind` to `Command` switch.
- `Sources/AppBundle/command/parseCommand.swift`: `parseCommand(String, allowExecAndForget:allowEval:)` for shell strings and `parseCommand([String])` for CLI args.
- `Sources/AppBundle/command/CmdEnv.swift`: implicit target (window id xor workspace name).
- `Sources/AppBundle/command/CmdIo.swift`: `CmdIo` (stdout/stderr line buffers, stdin), `CmdStdin`, `CmdResult`.
- `Sources/AppBundle/command/cmdResolveTargetOrReportError.swift`: `--window-id`/`--workspace`/env/focus resolution.
- `Sources/AppBundle/command/format.swift`, `Sources/AppBundle/command/formatToJson.swift`: `%{var}` interpolation for `list-* --format`, `test` and `--json` output.
- `Sources/AppBundle/command/impl/`: one `<Name>Command.swift` per command.

Generated and docs: `Sources/Common/cmdHelpGenerated.swift` (help text),
`Sources/Cli/subcommandDescriptionsGenerated.swift` (the `aerospace --help` list), per-command
asciidoc pages `aerospace-<name>.adoc` in `docs/`, `docs/commands.adoc`, and the completion grammar
`grammar/commands-bnf-grammar.txt`.

## How it works

### Declaring args

A command's args are a struct conforming to `CmdArgs` (`Withable`, `Equatable`, `Sendable`) with:

- `commonState: CmdArgsCommonState`: the raw args (only for `description`), `windowId`,
  `workspaceName`, `explicitStdinFlag`. `--window-id`/`--workspace` write into this, which is why
  `resolveTargetOrReportError` can read them generically.
- `static let parser: CmdParser<Self>`: `kind`, `help: <name_with_underscores>_help_generated`,
  `flags: [String: ArgParser]` (each one a writable keypath + parse function), ordered `posArgs`,
  `conflictingFlags: [Set<String>]`, `flagAllowlist` (flag -> the only flags allowed with it).
- `typealias ExitCodeType` when not `BinaryExitCode`.

Mandatory positionals are `Lateinit<T>` fields filled by `newMandatoryPosArgParser`; read them
with `.val` in `run`.

`initSubcommands()` registers either `SubCommandParser(XCmdArgs.init)` (generic parse only) or
`SubCommandParser(parseXCmdArgs)`, a function that calls `parseSpecificCmdArgs` and chains
`.filter`/`.filterNot` for cross-field rules (see `parseFocusCmdArgs`, `parseWorkspaceCmdArgs`).

`parseSpecificCmdArgs` walks args once: `-h`/`--help` (before a `--`) returns `.help(info.help)`;
anything `isCliDashFlag` (starts with `-`, isn't `-` or `--`) must be a key in `flags`, else
"Unknown flag" and stop; duplicate flags are errors; everything else goes to the next positional
parser, else "Unknown argument". Then: missing mandatory positionals, `conflictingFlags`,
`flagAllowlist`. Errors accumulate and come back as one `.failure` (exit 2 by default:
`ParsedCmd.failure(msg)` uses `T.ExitCodeType.fail`). The one hard-coded hack:
`isResizeNegativeUnitsArg` stops `resize width -50` from being read as a flag.

### Where parsing happens

- CLI: `Sources/Cli/_main.swift` calls `parseCmdArgs` locally, so `--help` and parse errors never
  reach the server, and `true`/`false` exit without connecting. It then sends the raw args
  (plus `AEROSPACE_WINDOW_ID`/`AEROSPACE_WORKSPACE` from its environment) to the server, which
  parses them again with `parseCommand([String])`: `parseCmdArgs` then `toCommand()`. No shell
  syntax on this path. Protocol details: [client-server.md](client-server.md).
- Config strings and `eval`: `parseCommand(String, ...)` lexes and parses the mini shell, then
  maps each leaf word list through the same `parseCommand([String])`
  ([shell-and-callbacks.md](shell-and-callbacks.md)).
- `toCommand()` refuses two kinds: `exec-and-forget` (only constructed directly by
  `parseCommand(String, allowExecAndForget: true)`, and absent from `subcommandParsers`, so the CLI
  says "Unrecognized subcommand") and `subscribe` (handled in `Sources/AppBundle/server.swift`
  before `parseCommand`; it has no `Command`).

### Running

```swift
protocol Command: AeroAny, Equatable, Sendable {
    associatedtype T: CmdArgs
    var args: T { get }
    @MainActor func run(_ env: CmdEnv, _ io: CmdIo) async -> T.ExitCodeType
    var shouldResetClosedWindowsCache: Bool { get }
}
```

`run(env, io)` is the raw implementation. The extension `run(env, stdin) -> CmdResult` wraps the
command in `Shell.cmd(self)` and runs it through `Shell.run`, which after each leaf calls
`resetClosedWindowsCache()` if `shouldResetClosedWindowsCache`, then
`refreshModel_nonCancellable()` (`Sources/AppBundle/layout/refresh.swift`).

Output goes through `io.out`/`io.err`, which append lines and return `IoSideEffect` so failures
read `return .fail(io.err("..."))`. The server joins `CmdResult`'s lines with `\n` for the socket answer.

Entry points that run commands, each inside `runLightSession` (see
[layout-and-refresh.md](layout-and-refresh.md)): hotkeys (`Sources/AppBundle/config/HotkeyBinding.swift`),
socket requests (`Sources/AppBundle/server.swift`), the menu bar's enable and reload buttons
(`Sources/AppBundle/ui/MenuBar.swift`), startup's `after-startup-command`
(`Sources/AppBundle/initAppBundle.swift`). Callbacks run from inside an existing session.

### Targeting: `--window-id`, `--workspace`, env

`CmdArgs.resolveTargetOrReportError(env, io) -> LiveFocus?` picks the first of:

1. `--window-id` flag (error if the id is unknown or the window has no monitor),
2. `--workspace` flag,
3. `env.windowId`, 4. `env.workspaceName`,
5. `globalFocus`.

The flags exist only on commands that put `windowIdSubArgParser()` / `workspaceSubArgParser()` in
their `flags`; the env fallback applies to every command whose `run` calls
`resolveTargetOrReportError` (24 of them). `CmdEnv` is set from the CLI request's
`windowId`/`workspace` fields (the client's `AEROSPACE_WINDOW_ID`/`AEROSPACE_WORKSPACE`), by
callbacks (`env.withFocus`, `env.withWindowId`), and is `.defaultEnv` (empty) for hotkeys.
`CmdEnv.asMap` turns it back into those env vars for `exec-and-forget`, which is how an
`aerospace` call from a callback script targets the callback's window.

### Exit codes

| Type | Values | Used by |
|---|---|---|
| `BinaryExitCode` (default) | 0 succ, 2 fail | most commands |
| `ConditionalExitCode` | 0 true, 1 false, 2 fail | `test`, `test-not`, `true`, `false` |
| `Int32ExitCode` | any | composites that pass through a child's code: `eval`, `run-callback`, `trigger-binding` |

Parse failures and unknown subcommands are 2. `Shell.run` returns `Int32ExitCode`.

### Help, docs, completion

- Help text is generated from the docs. `script/generate-cmd-help.sh` takes the
  `tag::synopsis` block of each `aerospace-<name>.adoc` in `docs/`, rewrites the first `aerospace`
  to `USAGE:` and the rest to `OR:`, and emits `let <name>_help_generated` (dashes to underscores)
  into `Sources/Common/cmdHelpGenerated.swift`. `generate.sh` runs it (skipped with
  `--ignore-cmd-help`, which `build-debug.sh` passes because it takes ~300 ms) and also writes
  `Sources/Cli/subcommandDescriptionsGenerated.swift` from each page's `:manpurpose:`, skipping
  `exec-and-forget`.
- Each `aerospace-<name>.adoc` is a man page with `purpose`, `synopsis` and `body` tags;
  `docs/commands.adoc` hand-lists every command with three `include::` lines. `build-docs.sh`
  builds the site (stripping the `aerospace ` prefix from synopses) and man pages. Shared flag
  text is in `docs/util/window-id-flag-desc.adoc` and `docs/util/workspace-flag-desc.adoc`.
- `grammar/commands-bnf-grammar.txt` is complgen's grammar; `build-shell-completion.sh` (run only
  by `build-release.sh`) generates zsh/fish/bash scripts and only checks they source cleanly.
  `{{{ aerospace ... }}}` in the grammar runs a live command for completions.

### What has to stay in sync, and what checks it

| Pair | Checked by |
|---|---|
| `CmdKind` case, `initSubcommands()` case, `toCommand()` case | the compiler (exhaustive switches) |
| `toCommand()` constructs the right `Command` type | `check(command.info == Self.info)` at runtime |
| `help: <name>_help_generated` and the `.adoc` page | the compiler, once `cmdHelpGenerated.swift` is regenerated |
| committed generated files and the `.adoc` pages | `test.sh`: runs `generate.sh`, then `script/check-uncommitted-files.sh` |
| synopsis text and the parser's actual flags | nothing |
| `docs/commands.adoc` includes and the set of pages | nothing |
| `grammar/commands-bnf-grammar.txt` and the parser | nothing (`build-release.sh` checks syntax only) |
| unused args/commands | periphery in `lint.sh` |

## Adding a command

Upstream's checklist from `dev-docs/architecture.md`, filled out to what the code requires:

1. Add a `CmdKind` case (kept sorted; raw value is the CLI name).
2. Write `<Name>CmdArgs.swift` in `Sources/Common/cmdArgs/impl/`: `commonState`, `parser` with
   `help: <name>_help_generated`, flags, positionals, `ExitCodeType` if not binary, and a
   `parse<Name>CmdArgs` with filters if fields interact. Decide whether `--window-id` and/or
   `--workspace` make sense; if so add the stock sub-arg parsers.
3. Register it in `initSubcommands()`.
4. Write `<Name>Command.swift` in `Sources/AppBundle/command/impl/`. Use
   `resolveTargetOrReportError` if the command acts on a window/workspace. Set
   `shouldResetClosedWindowsCache = true` if it can change the tree.
5. Add the case to `toCommand()` (or return `.failure`, which also blocks the CLI path unless
   `Sources/AppBundle/server.swift` handles it first, as it does `subscribe`).
6. Write `aerospace-<name>.adoc` in `docs/` (copy an existing page's tag structure) and add its three
   includes to `docs/commands.adoc`. Check the `build-docs.sh` output: `commands.html` in `.site`, and
   `.man`.
7. Run `./generate.sh` (or `script/generate-cmd-help.sh`) so the `_help_generated` symbol exists,
   and commit the regenerated `Sources/Common/cmdHelpGenerated.swift` and
   `Sources/Cli/subcommandDescriptionsGenerated.swift`.
8. Add the grammar to `grammar/commands-bnf-grammar.txt`.
9. Tests in `Sources/AppBundleTests/command/`: parse cases with `testParseCommandFail` /
   `testParseSingleCommandSucc` / `parseCommand("...").errorOrNil`, behaviour with
   `parseCommand("...").cmdOrDie.run(.defaultEnv, .emptyStdin)` (helpers in
   `Sources/AppBundleTests/testUtil.swift` and `Sources/AppBundleTests/assert.swift`; the test `parseCommand` allows both `exec-and-forget`
   and `eval`).
10. `./test.sh` (needs a clean tree for its last step).

## Rules worth keeping

- **Parsing runs twice, in two processes.** Anything in a `CmdArgs` parser runs in the CLI too, so
  it must not touch server state (windows, config, monitors). Validation that needs state goes in
  `run`.
- **Compose commands with `run(env, io)`, not `run(env, stdin)`.** The latter goes through
  `Shell.run`, adding a `refreshModel_nonCancellable` (and maybe a closed-windows-cache reset) per
  call. `CloseAllWindowsButCurrentCommand`, `TestNotCommand`, `MoveCommand` and `WorkspaceCommand`
  call sub-commands the cheap way.
- **Every CLI command is a full light session, queries included.** `server.swift` wraps every
  command, `list-windows` too, in `runLightSession`: a native-focus AX query, two
  `refreshModel_nonCancellable` calls plus one per leaf, `layoutWorkspaces()`, and a scheduled
  cancellable heavy refresh. A status bar polling `aerospace list-*` drives layout passes.
  `aerospace eval 'a; b; c'` pays for one session instead of three, plus one process spawn and
  socket round trip instead of three; `subscribe` avoids polling entirely.
- **`Int32ExitCode.succ` is 2, not 0** (`public static let succ = Int32ExitCode(rawValue: EXIT_CODE_TWO)`).
  `RunCallbackCommand` (`--for-every-window` with no windows) and `onWindowDetected` (no callback
  matched) start from it, so they report 2 when nothing ran. Use
  `Int32ExitCode(rawValue: EXIT_CODE_ZERO)` for success.
- **Flag values can't start with `-`.** `singleValueSubArgParser` uses `nonFlagArgOrNil`, so a
  value like `-1` reads as a missing value plus an unknown flag. Only `resize` is special-cased.
- **`-h`/`--help` anywhere before `--` wins**, even mid-args; `eval` refuses help inside its
  expression.
- **Equality is by args.** `Command ==` compares `args`; config tests and `HotkeyBinding ==`
  (`strictEquals`) depend on it, and `parseFocusCmdArgs` uses struct equality to detect "only
  `--window-id` was given". Keep new fields `Equatable` and defaulted.
- **Editing a synopsis needs a regenerate.** `build-debug.sh` skips help generation, so a changed
  `.adoc` synopsis shows stale `--help` until `generate.sh` runs; `test.sh` fails on the diff.
