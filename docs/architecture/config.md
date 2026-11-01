---
sources: ["Sources/AppBundle/config/", "docs/config-examples/"]
description: "Where the TOML config is found, how it is parsed into the Config struct and validated, how reload and auto-reload swap it in, and how modes and hotkeys, gaps, monitor assignment and on-window-detected are represented, for sessions adding or changing a config option."
---
# Config

The user's `.aerospace.toml` (or the XDG-path `aerospace.toml`) is parsed into one immutable `Config` value held in the
`@MainActor var config`. Everything else reads that global at use time; reload swaps it and
re-syncs the few things derived from it (hotkeys, file watcher, start-at-login, focus-follows-mouse).

**History:** upstream's `git log` for these paths;
`dev-docs/architecture.md` (upstream, stale; its "TOML Config parse subsystem" section is a todo).
User docs: `docs/guide.adoc`.

- `Sources/AppBundle/config/Config.swift`: the `Config` struct and its field defaults, `ConfigVersion`, `defaultConfigUrl`, the `defaultConfig`, `config` and `configUrl` globals.
- `Sources/AppBundle/config/ConfigFile.swift`: `findCustomConfigUrl()`, candidate paths.
- `Sources/AppBundle/config/parseConfig.swift`: `readConfig`, `parseConfig`, the top-level key table `configParser`, `Parser`/`ParserProtocol`, `ConfigParseDiagnostic`/`ConfigBacktrace`, scalar parsers, `parseShellOfCommandsForConfig`.
- `Sources/AppBundle/config/ConfigFileWatcher.swift`: `auto-reload-config` (DispatchSource file watcher, 200 ms debounce).
- `Sources/AppBundle/config/Mode.swift`, `Sources/AppBundle/config/HotkeyBinding.swift`: `[mode.*.binding]` parsing, `HotkeyBinding`, hotkey registration and `activateMode_nonCancellable`.
- `Sources/AppBundle/config/parseKeyMapping.swift`, `Sources/AppBundle/config/keysMap.swift`: `key-mapping` (preset + overrides), key-notation to `Key` tables, `modifiersMap`.
- `Sources/AppBundle/config/parseGaps.swift`, `Sources/AppBundle/config/DynamicConfigValue.swift`: `Gaps`, `ResolvedGaps`, per-monitor values.
- `Sources/AppBundle/config/parseWorkspaceToMonitorAssignment.swift`: `workspace-to-monitor-force-assignment`.
- `Sources/AppBundle/config/parseOnWindowDetected.swift`: `[[on-window-detected]]` into `WindowDetectedCallback`.
- `Sources/AppBundle/config/parseExecEnvVariables.swift`: `[exec]` into `ExecConfig`.
- `Sources/AppBundle/config/parseFocusFollowsMouse.swift`, `Sources/AppBundle/config/startAtLogin.swift`: small option tables and `SMAppService` sync.
- `docs/config-examples/default-config.toml`: the config used when the user has none (bundled as an app resource via `xcode/project.yml`); `docs/config-examples/i3-like-config-example.toml`: an example both parsed by tests.
- Reload itself is `reloadConfig_nonCancellable` in `Sources/AppBundle/command/impl/ReloadConfigCommand.swift`.

## How it works

### Lookup

`findCustomConfigUrl()` checks, on every reload:

- the server's `--config-path <path>` if given (exclusive; startup exits if the file is missing),
- otherwise both `.aerospace.toml` in `$HOME` and `aerospace.toml` in an `aerospace` directory
  under `$XDG_CONFIG_HOME` (default: `.config` in `$HOME`).

Both existing is an "Ambiguous config" error that blocks the reload (not a crash); neither means `defaultConfigUrl`: the bundled
`default-config.toml`, or in unit tests and non-bundle debug builds,
`docs/config-examples/default-config.toml` found by walking up from `#filePath` to `.git`.

At startup `initAppBundle` first reloads from `defaultConfigUrl` and `check`s it has no errors
(a corrupted install crashes here), then reloads the user config, then starts the socket server
and observers.

### Parsing

TOML is parsed by `TOMLDecoder` (dduan/TOMLDecoder 0.4.5, `TOMLTable(source:)`) into
`[String: Any]`, then `tomlAnyToOrderedJsonRecursive` turns it into `OrderedJson`. Table keys are
iterated sorted (`dict.sortedEntries`), so file order of table keys is lost; array order is
kept. Unsupported TOML types (floats, dates) become errors.

Keys map to fields through tables of `Parser(keyPath, parseFn)`:

- `configParser` in `Sources/AppBundle/config/parseConfig.swift` is the top level. `parseTable`
  walks the TOML table; an unknown key is an error ("Unknown top-level key" / "Unknown key"),
  otherwise the parser's value is written with `Withable.with(keyPath, value)`.
- Nested tables (`gaps`, `gaps.inner`, `gaps.outer`, `exec`, `focus-follows-mouse`, `key-mapping`, each
  `on-window-detected` entry) use their own parser tables via `parseNonEmptyTable`, which also
  rejects empty tables.
- `config-version`, `key-mapping` and `mode` are skipped by the table pass and parsed explicitly
  (`config-version` before it, the other two after), `key-mapping` before `mode` because binding keys are resolved through it.

Post-pass rules in `parseConfig`: under `config-version = 1`, `persistent-workspaces` is an error
and is instead derived from every `workspace`/`move-node-to-workspace` target in bindings plus the
`workspace-to-monitor-force-assignment` keys; `split` in any binding with
`enable-normalization-flatten-containers = true` is an error; a version below
`ConfigVersion.max` (2) gives a warning.

### Defaults

Defaults are the field initialisers of `struct Config` (and the nested structs), not
`default-config.toml`. A user config is parsed starting from `Config()`, never merged onto the
default file, so an omitted key gets the Swift default: no modes (and no error, since the `main`
mode check runs only when `mode` is present), zero gaps, empty callbacks. The default file's
comments ("Fallback value (if you omit the key)") describe those Swift defaults.
`ExecConfig()`'s default is the server environment with `PATH` prefixed by
/opt/homebrew/bin:/opt/homebrew/sbin.

### Diagnostics

Every parser appends `ConfigParseDiagnostic(backtrace, message, preventConfigReload:)` to the
context's `errors` or `warnings` and carries on; one bad key doesn't stop the parse.
`ConfigBacktrace` renders as `mode.main.binding.alt-h` or `on-window-detected[2].run`.
`preventConfigReload` is set only for severe failures: TOML syntax errors, an unreadable file, or
ambiguous config files.

### Reload

`reloadConfig_nonCancellable(args:forceConfigUrl:)`, shared by `reload-config`, the menu bar
button, startup and the file watcher:

1. `readConfig` (lookup, read, `parseConfig`).
2. Unless `--no-gui`: show errors (or warnings with `--warnings-as-errors`) in the
   `MessageModel` window, or clear it.
3. If no diagnostic has `preventConfigReload` and not `--dry-run`: `resetHotKeys()`, assign
   `config` and `configUrl`, `activateMode_nonCancellable(activeMode)`, `syncStartAtLogin()`,
   `syncFocusFollowsMouse(config)`, `syncConfigFileWatcher()`.
4. Return errors on stdout, warnings on stderr (on stdout as errors with `--warnings-as-errors`);
   failure if any errors.

So a config with ordinary errors is applied, minus the bad entries, and the command still exits
non-zero. Re-activating the same mode doesn't fire `on-mode-changed`.

`auto-reload-config = true`: `ConfigFileWatcher` opens `configUrl` with `O_EVTONLY` and watches
write/delete/rename/revoke on the main queue. Events are debounced 200 ms, then
`runLightSession(.configAutoReload)` runs the reload, whose `syncConfigFileWatcher()` reopens the
path, so editors that save by rename keep being watched.

### Modes and hotkeys

`[mode.<name>.binding]` tables map `modifier-...-key` strings to command strings. `parseBinding`
splits on `-`: all but the last part must be in `modifiersMap` (`shift`, `alt`, `ctrl`, `cmd`),
the last must be in `config.keyMapping.resolve()` (the `qwerty`/`dvorak`/`colemak` preset plus
`key-notation-to-key-code` overrides). Commands are parsed at load by
`parseShellOfCommandsForConfig` into `Shell<any Command>`
([shell-and-callbacks.md](shell-and-callbacks.md)). A binding is keyed by
`descriptionWithKeyCode` (modifiers in a fixed order, then the key), so `alt-shift-h` and
`shift-alt-h` collide as "Binding redeclaration".

Registration uses soffes/HotKey 0.2.1 (Carbon global hotkeys). `activateMode_nonCancellable`:

- creates a `HotKey` for every binding of the target mode not already in the `hotkeys` dict
  (keyed by `descriptionWithKeyCode`), then enables exactly the target mode's keys. `isEnabled`
  maps to HotKey's `isPaused`, which (per HotKey, not this repo) unregisters/re-registers with the system. The dict grows
  across modes until `resetHotKeys()` on reload.
- updates `activeMode`; if it changed, broadcasts `mode-changed` and runs `on-mode-changed`.

A keypress runs an unstructured task: broadcast `binding-triggered`, then
`runLightSession(.hotkeyBinding, .checkServerIsEnabledOrDie())`, which looks the binding up in the
current `config.modes[activeMode]` by key code (not the captured binding) and runs it with
`.defaultEnv`. `mode <name>` and `enable` call `activateMode_nonCancellable`; `trigger-binding`
finds a binding by its key-notation string. `config --get` exposes only the `mode` subtree
(`buildConfigMap`), see [commands.md](commands.md).

### Gaps

`gaps.inner.{horizontal,vertical}` and `gaps.outer.{left,bottom,top,right}` are each a
`DynamicConfigValue<Int>`: a constant, or an array `[{ monitor.<description> = n }, ..., default]`.
`ResolvedGaps(gaps:monitor:)` resolves all six for one monitor; it's built in
`Sources/AppBundle/layout/layoutRecursive.swift` (per workspace layout) and
`Sources/AppBundle/model/MonitorInfoEx.swift`. A per-monitor value takes the first rule whose
description resolves to a monitor with the same top-left corner.

### Monitor descriptions and assignment

`parseMonitorDescription` (`Sources/Common/model/MonitorDescription.swift`): an int >= 1 is a
1-based sequence number (monitors sorted by x then y), `main`, `secondary` (resolves only when
exactly two monitors are connected), anything else a case-insensitive regex on the monitor name
(first match in sorted order). Resolution is `resolveMonitorInfo` in
`Sources/AppBundle/model/MonitorDescriptionEx.swift`. `workspace-to-monitor-force-assignment` maps a
workspace name to one description or a list (first that resolves wins). It's applied by
`Workspace.forceAssignWorkspaces()` (`Sources/AppBundle/tree/Workspace.swift`) on every
`refreshModel_nonCancellable`, through `forceAssignedMonitorInfo` in
`Sources/AppBundle/tree/WorkspaceEx.swift`.

### on-window-detected

An array of tables with `if`, `check-further-callbacks`, `run`. `if` is either a table (`app-id`,
`app-name-regex-substring`, `window-title-regex-substring`, `workspace`,
`during-aerospace-startup`; regexes compiled at parse time) or a command string (no
`exec-and-forget`). Omitting `if` without `check-further-callbacks` is an error; `run` is
mandatory. Each entry parses into its own context, and an entry with any error is dropped whole.
Matching and execution: [shell-and-callbacks.md](shell-and-callbacks.md#callbacks).

### Other keys and where they're read

`accordion-padding` (`Sources/AppBundle/layout/layoutRecursive.swift`),
`automatically-unhide-macos-hidden-apps` (`Sources/AppBundle/GlobalObserver.swift`,
`Sources/AppBundle/normalizeLayoutReason.swift`), `persistent-workspaces`
(`Sources/AppBundle/tree/Workspace.swift`), `default-root-container-layout`/`-orientation`
(`Sources/AppBundle/tree/WorkspaceEx.swift`), `focus-follows-mouse`
(`Sources/AppBundle/mouse/focusFollowsMouse.swift`), `start-at-login`
(`SMAppService.mainApp`; `true` only prints a notice in debug builds), `exec` (`exec-and-forget` and
`exec-on-workspace-change`). `after-login-command`, `indent-for-nested-containers-with-the-same-orientation`
and `non-empty-workspaces-root-containers-layout-on-startup` are deprecated and parse only to
produce an error (empty `after-login-command` and `'smart'` are accepted).

## Performance

- Parsing (`parseConfig` is `@MainActor`) and hotkey re-registration happen on the main actor,
  only at startup and reload. Command strings and regexes are compiled then, not per use.
- A hotkey press costs a full `runLightSession`: native-focus AX query, refreshes, layout and a
  scheduled heavy refresh ([layout-and-refresh.md](layout-and-refresh.md)), plus a refresh per
  leaf command.
- Per-monitor gap values and force-assignment descriptions are re-resolved on every use, and each
  resolution reads `globalSortedMonitorInfos`, which enumerates `NSScreen.screens` and sorts.
  `ResolvedGaps` does that once per per-monitor field (up to six per workspace layout), and
  `forceAssignWorkspaces()` once per assigned workspace on every `refreshModel_nonCancellable`.
  Constant gaps and configs without force assignment skip it.

## Rules worth keeping

- **Adding an option:** a field with a default on `Config` (or a nested struct), a `Parser` entry
  in `configParser` (otherwise it's "Unknown top-level key"), handling of derived state in
  `reloadConfig_nonCancellable` if anything is computed from it, a case in
  `Sources/AppBundleTests/config/ConfigTest.swift`, and user docs in `docs/guide.adoc`. The
  comment above `configParser` asks to prefer commands and flags over new TOML options.
- **Both example configs must parse with zero errors and zero warnings.** `ConfigTest` asserts
  it for `default-config.toml` and `i3-like-config-example.toml`; a new warning or a deprecation
  breaks the test until the examples are updated.
- **Read `config` at use time.** Reload replaces the whole struct; anything cached from it goes
  stale unless reload re-syncs it explicitly, like hotkeys and the watcher do.
- **Non-severe errors don't block reload.** The applied config is whatever parsed; dropped keys
  fall back to Swift defaults. Don't rely on "errors mean the old config stays".
- **An `[exec]` table replaces the default exec env.** `RawExecConfig.expand()` builds from the
  inherited env plus `env-vars`, without the Homebrew `PATH` prefix the default `ExecConfig()`
  adds. `env-vars` values interpolate `${VAR}` against the server env; `PWD` can't be set.
- **Table key order is irrelevant; array order is significant.** `on-window-detected` priority is
  array order.
- **The watcher dies with the file.** If `configUrl` can't be opened when
  `syncConfigFileWatcher()` runs, `ConfigFileWatcher.init` returns nil and auto-reload stops
  until the next applied reload. The watcher is only re-armed when a reload is applied, so a save
  with a TOML syntax error keeps the old file descriptor, which after a rename-style save points
  at the replaced file.
