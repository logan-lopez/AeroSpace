---
sources: ["Sources/AppBundle/shell/", "Sources/Common/model/AeroSpaceEnvVars.swift"]
description: "AeroSpace's mini shell (lexer, parser, &&/||/;/|, eval), exec-and-forget and exec-on-workspace-change process spawning, the AEROSPACE_* env vars, and where each config callback is dispatched and what it costs, for sessions touching command strings, callbacks or scripting performance."
---
# Shell and callbacks

Command strings in the config (bindings, callbacks) and in `aerospace eval` are written in a small
shell language, parsed once into a `Shell<any Command>` tree and run on the main actor. Callbacks
are such trees, run from inside refresh sessions; `exec-*` hooks spawn external processes.

**History:** upstream's `git log` for these paths and the four command files below;
`dev-docs/architecture.md` (upstream, stale; doesn't cover this area). User-facing syntax and callbacks
are the "Shell" and "Callbacks" sections of `docs/guide.adoc`.

- `Sources/AppBundle/shell/shellLexer.swift`: character state machine to `LexerToken`s with line/column locations.
- `Sources/AppBundle/shell/shellParser.swift`: recursive-descent parser to `Shell<[String]>`; the grammar is in its header comment.
- `Sources/AppBundle/shell/Shell.swift`: the `Shell<T>` enum, `flatMap` (words to commands), and `Shell.run` with the and/or/seq/pipe semantics.
- `Sources/AppBundle/command/parseCommand.swift`: `parseCommand(String, allowExecAndForget:allowEval:)`, the entry point that special-cases `exec-and-forget`.
- `Sources/AppBundle/command/impl/EvalCommand.swift`, `Sources/AppBundle/command/impl/ExecAndForgetCommand.swift`, `Sources/AppBundle/command/impl/ListExecEnvVarsCommand.swift`, `Sources/AppBundle/command/impl/RunCallbackCommand.swift`: the shell-adjacent commands (declared like any other, see [commands.md](commands.md)).
- `Sources/Common/model/AeroSpaceEnvVars.swift`: the four `AEROSPACE_*` env var names.
- Dispatch sites owned by other pages: `Sources/AppBundle/focus.swift` (focus/workspace/monitor callbacks), `Sources/AppBundle/tree/MacWindow.swift` (`on-window-detected`), `Sources/AppBundle/config/HotkeyBinding.swift` (`on-mode-changed`), `Sources/AppBundle/initAppBundle.swift` (`after-startup-command`).

## How it works

### Lexer

Tokens: word, `&&`, `||`, `|`, `(`, `)`, `;`, newline, end. Quoting is `'...'` or `"..."` with no
escapes and no interpolation inside; a closing quote must be followed by whitespace or an operator, and a quote
can't start mid-word. Bare words may not contain `` ( ) $ ~ & ? * ! \ | < > ` ' " # `` or newline
(except the literal word `~=`, the `test` operator); the error tells the user to quote. `#` starts
a comment. `\` is only a line continuation: it may be followed by whitespace, a newline or a
comment, nothing else. A newline directly before `&&`, `||` or `|` is an error ("Please escape
newline"). Errors carry `Line N Column M`.

### Parser

```
Seq  = Or ((";" | "\n")+ Or?)*
Or   = And ("||" And)*
And  = Pipe ("&&" Pipe)*
Pipe = "(" Seq ")" | Cmd ("|" Cmd)*
Cmd  = Word+
```

Precedence is pipe > `&&` > `||` > `;`. Unlike POSIX sh, `&&` binds tighter than `||`:
`a || b && c` is `a || (b && c)`. Two commands separated only by newlines are an error ("Please
use explicit semicolon"); trailing newlines are fine. A parenthesised group can't be piped.
`Shell.newCompound` collapses one-element lists, so `.and`/`.or`/`.seq`/`.pipe` always have 2+
children.

`Shell<[String]>.flatMap(parseCommand)` turns each leaf's words into a `Command` through the
normal CLI parser; one bad leaf fails the whole string.

`parseCommand(String, ...)` checks first: if `allowExecAndForget` and the raw string
`starts(with: "exec-and-forget")`, the entire remainder (leading space included) becomes
`ExecAndForgetCmdArgs.bashScript` and no lexing happens. Otherwise lex, parse, map, and reject
`eval` leaves unless `allowEval`.

| Caller | `allowExecAndForget` | `allowEval` |
|---|---|---|
| config command values (`parseShellOfCommandsForConfig`: bindings, callbacks, `run`) | true | false |
| `on-window-detected` `if = '<command>'` matcher | false | false |
| `EvalCommand` | false | false |
| tests (`Sources/AppBundleTests/testUtil.swift`) | true | true |

A config value may be a string or an array of strings; an array becomes a `.seq`, each element
parsed separately (so `exec-and-forget` can be one element of an array).

### Running a `Shell`

`Shell<any Command>.run(env, io) -> Int32ExitCode` (all `@MainActor`):

- leaf: `command.run(env, io)`, then `resetClosedWindowsCache()` if the command asks for it, then
  `refreshModel_nonCancellable()`.
- `.and`: stop at first non-zero; `.or`: stop at first zero (returns the last code; 2 if empty);
  `.seq`: run all, return the last code; `.empty`: 0.
- `.pipe`: run left to right, each command's stdout joined with `\n` becomes the next one's stdin,
  stderr accumulates on the outer io, only the last stdout is emitted, exit code is the rightmost
  non-zero (pipefail). Only `workspace` and `move-node-to-workspace` with `--stdin` read stdin.

`env` (a `CmdEnv`) is passed unchanged to every leaf.

### `eval`

`eval [--stdin] [--] <expr>` parses `<expr>` at run time with `allowEval: false`,
`allowExecAndForget: false` and runs it with the request's env and io. Because config strings also
use `allowEval: false`, `eval` is effectively CLI-only. `--stdin` makes the CLI forward its stdin,
which pipes reach via `CmdIoForwardingStdin`. `--help` inside the expression is refused.

### External processes

`exec-and-forget <script>` (`ExecAndForgetCommand`): `Process` running /bin/bash with `-c <script>`,
`environment = config.execConfig.envVariables + env.asMap`, `try process.run()`. It doesn't wait,
ignores the child's exit status, and returns success iff the launch didn't throw. The code doesn't
ask for a new session or process group (a `todo` in the code asks whether it should).

`exec-on-workspace-change = ['<executable>', '<arg>', ...]` (`onWorkspaceChanged` in
`Sources/AppBundle/focus.swift`): `Process` with the first element as the executable (no shell)
and the rest as args. Environment: `config.execConfig.envVariables` plus
`AEROSPACE_FOCUSED_WORKSPACE`, `AEROSPACE_PREV_WORKSPACE`, and either `AEROSPACE_WORKSPACE`
(focus is an empty workspace) or `AEROSPACE_WINDOW_ID`. Launch errors are swallowed.

`config.execConfig.envVariables` is the server's own environment plus `PATH` prefixed with
/opt/homebrew/bin:/opt/homebrew/sbin, unless the config has an `[exec]` table (parsed in
`Sources/AppBundle/config/parseExecEnvVariables.swift`, see [config.md](config.md)).
`list-exec-env-vars` prints exactly that map; it never includes the per-invocation `AEROSPACE_*`
vars.

Child processes that call `aerospace` inherit `AEROSPACE_WINDOW_ID`/`AEROSPACE_WORKSPACE`; the CLI
forwards them and the server makes them the default target (see
[commands.md](commands.md)). That is how
`exec-and-forget aerospace move-node-to-workspace 3` in an `on-window-detected` callback moves the
detected window, not the focused one.

### Callbacks

| Config key | Dispatched from | Env | When |
|---|---|---|---|
| `after-startup-command` | `initAppBundle()` in `Sources/AppBundle/initAppBundle.swift`, inside `runLightSession(.startup)` | default | once, after the startup heavy refresh |
| `on-focus-changed` | `checkOnFocusChangedCallbacks_nonCancellable` in `Sources/AppBundle/focus.swift` | `withFocus(focus)` | focused window or workspace differs from `_lastKnownFocus` |
| `exec-on-workspace-change` | same, via `onWorkspaceChanged` | process env above | focused workspace name changed |
| `on-focused-monitor-changed` | same | `withFocus(focus)` | focused monitor id changed |
| `on-mode-changed` | `activateMode_nonCancellable` in `Sources/AppBundle/config/HotkeyBinding.swift` | default | active mode actually changed |
| `on-window-detected` | `runOnWindowDetected` / `onWindowDetected` in `Sources/AppBundle/tree/MacWindow.swift` | `withWindowId(window)` | a newly registered window (not one restored from the closed-windows cache) whose parent isn't the popup container; also `Sources/AppBundle/normalizeLayoutReason.swift` when a window parked as a popup later passes the window heuristic |

`checkOnFocusChangedCallbacks_nonCancellable` is called by every `refreshModel_nonCancellable`, i.e.
twice per light session (once per heavy one) and once per leaf command. It returns early during startup. It
updates `_lastKnownFocus` (and `_prevFocus`, `_prevFocusedWorkspaceName`, used by the
back-and-forth commands) before checking `onFocusChangedRecursionGuard`, so focus changes made by
a callback's own commands are absorbed silently rather than re-firing callbacks.

`on-window-detected`: `config.onWindowDetected` is walked in order; for each callback whose
matcher passes, `run` executes, and the walk stops unless `check-further-callbacks = true`.
Matchers: the legacy table (`app-id` exact, `app-name-regex-substring`,
`window-title-regex-substring`, `workspace`, `during-aerospace-startup`) or a command string whose
exit code 0 means match. A pending `layout --for-next-detected-window` is applied both before
the callbacks and again (in a `defer`) after them. `run-callback` re-runs `on-window-detected`
(optionally `--for-every-window`), `on-focus-changed` or `on-focused-monitor-changed` by hand.

Each dispatcher also calls `broadcastEvent` before running the config callback: `focus-changed`,
`focused-workspace-changed`, `focused-monitor-changed`, `mode-changed`, `window-detected`;
hotkeys add `binding-triggered`. The `subscribe` registry and wire format are in
[client-server.md](client-server.md).

## Performance

- **Every leaf costs a model refresh.** `Shell.run` calls `refreshModel_nonCancellable()` after
  each leaf: workspace GC, `Workspace.forceAssignWorkspaces()`, the focus-callback check, and
  `normalizeContainers()`. A binding of five commands does that five times on top of the session's
  own two. Callback trees nest inside this, and each of their leaves refreshes again.
- **Spawning is synchronous on the main actor but doesn't wait.** Both `exec-and-forget` and
  `exec-on-workspace-change` call `Process.run()` from main-actor code; the main thread pays for
  the launch, the merged env dictionary, and nothing after. Bash startup and the script run in
  the child.
- **The expensive pattern is the round trip.** A script launched by `exec-*` that calls back into
  `aerospace` pays for a process launch, a socket connection, and a full `runLightSession` on the
  server per call (AX focus query, refreshes, `layoutWorkspaces()`, a scheduled heavy refresh).
  A workspace-change hook driving a status bar that then runs several `aerospace list-*` calls
  multiplies that on every workspace switch. Prefer `aerospace eval` (one session for many
  commands), pass data via the `AEROSPACE_*` env vars, or use `subscribe`.
- **Matchers aren't free.** `window-title-regex-substring` fetches the title over AX for every
  detected window, for every callback that reaches that check. A command-string `if` runs a full
  `Shell.run` (with a refresh per leaf) per window per callback. Put cheap `app-id` callbacks
  first and avoid `check-further-callbacks` chains that force evaluating later matchers.
- **Lexing and parsing happen at config load**, not per keypress, except for `eval`, which parses
  its string on every call.

## Rules worth keeping

- **`exec-and-forget` swallows the rest of the string.** `'exec-and-forget open -a Foo && workspace 1'`
  hands `open -a Foo && workspace 1` to bash. Use an array (`['exec-and-forget open -a Foo', 'workspace 1']`)
  to sequence an AeroSpace command after it.
- **`exec-and-forget` exists only in config.** It's not in `subcommandParsers`, `toCommand()`
  refuses it, and `eval` forbids it; from a terminal, just run the program.
- **`&&` binds tighter than `||`.** Configs ported from sh can change meaning; parenthesise.
- **Callbacks can't trigger themselves.** The recursion guard plus the early `_lastKnownFocus`
  update mean a `workspace` command inside `on-focus-changed` won't fire `on-focus-changed` or
  `exec-on-workspace-change` for the change it makes.
- **Env is window xor workspace.** `CmdEnv.withWindowId` clears the workspace and vice versa, so a
  callback script sees one of `AEROSPACE_WINDOW_ID` / `AEROSPACE_WORKSPACE`, never both
  (`exec-on-workspace-change` follows the same rule).
- **Exit code of `on-window-detected` with no match is 2**, because it starts from
  `Int32ExitCode.succ`, whose raw value is 2 ([commands.md](commands.md#rules-worth-keeping)).
  `run-callback on-window-detected` reports it.
- **Dispatch callbacks from inside a session.** All existing dispatchers run under
  `runLightSession` or `runHeavyCompleteRefreshSession` ([layout-and-refresh.md](layout-and-refresh.md)):
  `isStartup` (behind `during-aerospace-startup` and the startup skip of focus callbacks) reads
  the session's `refreshSessionEvent`, and windows are only laid out at the end of a session.
