# Retrl plugin API: plan

Status: proposal. Nothing here is implemented. Written against the code as of
commit `513d75b` (Godot 4.3, GDScript, autoload-based).

## 1. Goals and non-goals

**Goals**
- Let a plugin add its own **side-menu entries** (each opening a full page) and
  its own **tabs on the game detail pages** (`GameDetail` and `RecompDetail`).
- Let a plugin supply **library content** (detect games/carts), **launch
  behaviour** (args, env, working directory, pre/post hooks), and **settings**.
- Keep controller-first navigation working inside plugin UI.
- Isolate failures: a broken plugin must never take the launcher down.
- Reuse what Retrl already has (git-release installs, art, screenshots,
  achievements, process tracking) instead of reinventing it per plugin.

**Non-goals (v1)**
- A real security sandbox (see section 8; GDScript cannot be sandboxed).
- A plugin store/marketplace. Plugins are installed from a folder, a zip or a
  git release URL.
- Theming/replacing core screens. Plugins extend; they do not replace.

## 2. Today's code and what has to change

| Area | Today | Needed |
|---|---|---|
| Side menu | `Shell._build_side_menu()` hard-codes six `_add_menu_item` calls. | Build from a registry: core items plus plugin items, with ordering. |
| Pages | `Navigator.push(scene_path, args)` loads a `.tscn` and calls `set_args`. | Also accept a Callable/Control factory (`push_control`), so a plugin page needs no scene file. |
| Game detail tabs | `GameDetail.tscn` has two fixed buttons (`AchievementsTabButton`, `ScreenshotsTabButton`) and `_show_tab()` toggles two panes. | Replace with a dynamic tab bar built from a tab list (core tabs registered the same way plugins register theirs). |
| Recomp detail | Same hard-coded pattern, Screenshots only. | Same dynamic tab bar. |
| Library | `LibraryScanner.reload()` scans directories; Quiver is a special-cased `library_adapter`. | Generic **library source** hook; Quiver becomes the first built-in source. |
| Launch | `LaunchManager.launch(game)` resolves emulator + args template. | Hooks before/after launch; a game may carry its own launch spec. |
| Game ids | Plain strings; `recomp:<id>` for recomps. | Plugin games namespaced `plugin:<plugin_id>:<id>`. |

The refactor of tabs and menu to registries is worth doing even without
plugins; core features then use the same mechanism, which keeps the API honest.

## 3. Plugin package

```
user://plugins/<plugin_id>/
  plugin.json        manifest (required)
  main.gd            entry script (required), extends RetrlPlugin
  icon.png           optional, 128x128
  ui/*.tscn          optional scenes
  assets/            optional
```

Install sources: drop-in folder, `.zip`, or a git release (reusing
`UpdateManager`, so plugins get versions and updates the way emulators do).

### Manifest (`plugin.json`)

```json
{
  "id": "gen1recomp",
  "name": "Gen1Recomp",
  "version": "0.1.0",
  "api_version": 1,
  "min_retrl_version": "0.3.0",
  "author": "...",
  "description": "...",
  "entry": "main.gd",
  "permissions": ["library.provide", "launch.hooks", "process.spawn",
                  "fs.read:external", "fs.write:external", "net.http:github.com"],
  "depends_on": [],
  "credits": "Based on the Pokemon Gen 1 Recompilation Project by BOIS CLUB GAMES, LLC (https://github.com/bryanthaboi/gen1recomp)"
}
```

- `api_version` is an integer. Retrl refuses to load a plugin newer than it
  supports and flags older ones as "outdated" (never silently runs them).
- `credits` is shown on the plugin's pages and in a Retrl "About plugins"
  screen. This matters for licences that require visible attribution.
- `permissions` are a consent list shown at install time (section 8).

## 4. Lifecycle

1. **Discover**: scan `user://plugins/*/plugin.json` at startup (after the core
   autoloads exist).
2. **Validate**: manifest schema, `api_version`, `min_retrl_version`,
   dependency order, permission list.
3. **Enable check**: honour the per-plugin enabled flag in
   `user://plugins_state.json`. New plugins start **disabled** until the user
   approves the permission list.
4. **Load**: instantiate `main.gd`, giving it a `PluginContext` (its only
   handle to Retrl). Wrap every call into plugin code in a guard (section 9).
5. **Callbacks**: `_on_load(ctx)`, then registrations happen inside it.
6. **Unload / reload**: `_on_unload()`; the host removes everything the plugin
   registered (tracked per plugin id), so disabling takes effect without a
   restart where possible.
7. **Update**: via git releases; the new version loads on next start (hot
   reload only in a developer mode).

`RetrlPlugin` base class (host-provided):

```gdscript
class_name RetrlPlugin extends RefCounted
func _on_load(ctx: PluginContext) -> void: pass
func _on_unload() -> void: pass
func _on_settings_changed(key: String, value: Variant) -> void: pass
```

## 5. What plugins can register (extension points)

Every registration returns nothing and is tied to the plugin id. IDs are local
to the plugin; the host namespaces them as `<plugin_id>/<id>`.

### 5.1 Side-menu entries and pages

```gdscript
ctx.ui.add_menu_item({
  "id": "box",
  "label": "Pokémon Box",
  "icon": "res://...png" | Texture2D,    # optional
  "order": 50,                            # core items use 10, 20, 30...
  "section": "main",                      # "main" | "tools"
  "visible_if": func() -> bool: ...,      # optional, re-evaluated on menu open
  "open": func(nav) -> void: nav.push_page("box")   # or direct page factory
})

ctx.ui.add_page({
  "id": "box",
  "title": "Pokémon Box",                 # shown in the shell top bar
  "build": func(page_ctx, args) -> Control: ...,
  "on_show": func(): ..., "on_hide": func(): ...,
  "on_back": func() -> bool: ...          # return true to consume Back
})
```

- A page is a `Control` the plugin builds (or a `PackedScene` it instantiates).
  The host mounts it in the same host container `Navigator` uses today, so the
  top bar and side menu stay persistent.
- Pages participate in the existing navigation stack, so Back works.
- A menu entry may also run an action instead of opening a page (for example
  "Open OpenHome").

### 5.2 Game detail tabs

```gdscript
ctx.ui.add_game_tab({
  "id": "saves",
  "title": "Saves",
  "icon": ...,                            # optional
  "order": 30,                            # core: Achievements 10, Screenshots 20
  "applies_to": func(game: Dictionary) -> bool: return game.platform_id == "gb",
  "build": func(tab_ctx, game: Dictionary) -> Control: ...,
  "on_show": func(tab_ctx, game): ...,    # refresh when selected
  "on_hide": func(tab_ctx, game): ...
})
ctx.ui.add_recomp_tab({ ... same shape, game = recomp entry ... })
```

- `applies_to` is evaluated per game, so a tab can appear only for the games it
  understands (for example only for gen1recomp carts).
- The host owns the tab bar and focus handling. When a tab is shown, the host
  moves focus to the first focusable control in the plugin's pane (the same fix
  `GameDetail._grab_first_focusable` applies today), so controller users can
  always get in and out.
- `tab_ctx` provides `request_refresh()`, `set_busy(bool)`, `toast(text)`,
  `close_tab()` and a per-tab storage handle.
- Core tabs (Achievements, Screenshots) are re-implemented as registrations of
  the same API.

### 5.3 Other UI extension points

| Point | Purpose |
|---|---|
| `add_settings_pane(def)` | A tab inside **AppSettings** for plugin options. Either a declarative schema (see 5.8) or a custom `Control`. |
| `add_home_row(def)` | An extra row on Home (for example "Recent carts", "Plugin updates"). |
| `add_tile_badge(def)` | A small overlay on a game tile (for example a "Cart" label or save indicator). Predicate plus icon/text, cheap to evaluate. |
| `add_game_action(def)` | An extra button on the game page action row or in a context menu (for example "Back up save"). |
| `add_library_tab(def)` | An extra platform-style tab in Library (for example "Gen1Recomp carts"). |
| `add_game_detail_header(def)` | Extra info lines in the summary block (last played, platform, plugin facts). |
| `ui.toast / ui.confirm / ui.prompt / ui.pick_file / ui.pick_folder / ui.progress` | Shared dialogs (wrapping the existing system `FileDialog` usage). |

### 5.4 Library sources

```gdscript
ctx.library.add_source({
  "id": "carts",
  "scan": func(scan_ctx) -> Array[Dictionary]: ...,  # may be async
  "rescan_on": ["startup", "manual", "fs_change"],
  "watch_paths": [path]                                 # optional
})
```

A source returns **game dictionaries** in Retrl's existing shape
(`id`, `title`, `platform_id`, `rom_path`, `last_played`, art keys, etc.) plus:

- `source_plugin`: filled in by the host.
- `launch`: optional per-game launch spec (section 5.5).
- `meta`: free-form dictionary the plugin owns, returned to it on every
  callback (for example cart id, save slot list).
- `kind`: `"game"` (default) or `"recomp"`, selecting which detail page opens.

Other library calls: `ctx.library.get_games()`, `get_game(id)`,
`games_for_platform`, `set_display_name`, `set_override`,
`refresh()`. The Quiver adapter is migrated to this hook as the first built-in
source, which proves the interface.

### 5.5 Launch support

```gdscript
ctx.launch.add_hooks({
  "before_launch": func(game, spec) -> Dictionary:   # may modify spec or veto
     return {"ok": true, "spec": spec},
  "after_launch":  func(game, pid): ...,
  "after_exit":    func(game, exit_info): ...
})
```

`spec` is a dictionary the host will run:
`{"binary": String, "args": Array, "env": Dictionary, "cwd": String,
 "label": String, "screenshot_key": String}`.

- A game can carry its own `launch` spec instead of using an emulator. Retrl's
  existing single-process tracking, pause-the-launcher-while-playing state and
  concurrent-launch refusal all still apply.
- A hook can veto with a reason (shown to the user), for example "OpenHome is
  still open".
- `ctx.launch.run(spec)` lets a plugin start a **non-game helper** (for example
  OpenHome) under the same tracking, and `ctx.launch.run_detached(spec)` for
  fire-and-forget tools.
- `ctx.launch.is_running()` and the `game_started` / `game_stopped` signals are
  forwarded.

### 5.6 Managed external apps (emulator/recomp-style)

```gdscript
ctx.apps.register({
  "id": "openhome", "name": "OpenHome",
  "source": {"type": "git_releases", "repo": "andrewbenington/OpenHome",
             "asset_pattern": "*.AppImage"},
  "integration_mode": "tool"      # new: appears under Tools, not Emulators/Recomps
})
```

This reuses `EmulatorRegistry` and `UpdateManager` (install, versions, update
checks) with a new `integration_mode: "tool"` so such entries get their own
page and do not show up as emulators. The plugin can then call
`ctx.apps.launch("openhome", args)`.

### 5.7 Events (read-only subscriptions)

`ctx.events.on(name, callable)` / `off`. Planned events:

| Event | Payload |
|---|---|
| `app_ready` | none |
| `game_selected` | game |
| `game_detail_opened` / `game_detail_closed` | game |
| `game_started` / `game_stopped` | game, label |
| `library_reloaded` | none |
| `emulator_installed` / `emulator_activated` | emulator id, version |
| `screenshot_captured` | key, path |
| `controller_changed` | info |
| `settings_changed` | plugin id, key |

Plugins may also define and emit their own events, and listen to other
plugins' events when `depends_on` is declared.

### 5.8 Settings

```gdscript
ctx.settings.declare([
  {"key": "install_path", "type": "path", "label": "Gen1Recomp location", "default": ""},
  {"key": "auto_backup", "type": "bool", "label": "Back up saves before launch", "default": true},
  {"key": "api_key", "type": "secret", "label": "..."},
  {"key": "mode", "type": "choice", "choices": ["a", "b"]}
])
ctx.settings.get("key") / set("key", v)
```

Types: `bool`, `int`, `float`, `string`, `text`, `choice`, `path`
(file or folder, with the existing Browse button), `secret`, `button`
(runs a callback), `info`. The host renders these into a settings pane
automatically (controller friendly), and a plugin may supply a custom Control
instead.

## 6. Services the host exposes

| Namespace | What it provides |
|---|---|
| `ctx.log` | `debug/info/warn/error`, written to a per-plugin log shown in a plugin diagnostics screen. |
| `ctx.storage` | Per-plugin private JSON/KV store under `user://plugins_data/<id>/` (`get/set/delete`, `read_file/write_file` inside that folder). Per-game storage keyed by game id. |
| `ctx.fs` | Scoped file access beyond the private folder, gated by permission and (where possible) the user-approved paths: `read_text/read_bytes/write_*`, `list_dir`, `copy`, `exists`, `mkdir`, `hash_sha1/sha256`, atomic write helper, `backup(path, keep=N)`. |
| `ctx.http` | `get/post/download` with timeouts, progress and host allow-list from the manifest. Reuses `UpdateManager`'s timeout logic. |
| `ctx.process` | `spawn(spec)`, `run_and_capture(spec)` (blocking in a thread), `kill(pid)`, `is_running(pid)`. |
| `ctx.art` | Read/set cover and hero art for a game id, search SteamGridDB (using the user's existing key), using `ArtManager`. |
| `ctx.screenshots` | List/get screenshots for a key. |
| `ctx.achievements` | Read-only RetroAchievements lookups (reusing the user's credentials). |
| `ctx.platforms` / `ctx.emulators` | Read the registry; add a platform or emulator definition on behalf of the user (with confirmation). |
| `ctx.input` | Query controller type, register extra actions/hotkeys, map button hints (A/B/X/Y glyphs) for plugin UI. |
| `ctx.theme` | The shared SteamOS-style theme, colour tokens, standard widgets (section header, card, tile, toggle row, list row, tab bar, grid, empty-state, progress). |
| `ctx.app` | Retrl version, paths (data dir, downloads dir, screenshots dir), `open_url`, `quit`, `is_playing`. |
| `ctx.tasks` | Run work on a thread with progress, cancel and UI-safe completion callbacks. |
| `ctx.i18n` | (later) string tables per plugin. |
| `ctx.plugins` | Look up other loaded plugins and call their exported API (`ctx.plugins.get("x").api.method()`), for example a Box plugin used by a Gen1Recomp plugin. |

## 7. UI toolkit and controller rules

Plugin UI is where most inconsistency will come from, so ship:

- A set of **standard controls** in `ctx.theme` with focus handling built in
  (the repo has repeated `_grab_first_focusable` workarounds; fix once).
- A **focus contract**: the host guarantees a pane gets initial focus, that
  Back (B) leaves a plugin page unless `on_back` consumes it, and that the
  side menu opens with Start.
- **Button-hint bar**: pages can declare hints (`A Select  B Back  X Backup`)
  that the shell shows, using the active controller's glyph set.
- **Async-friendly**: builders may return a placeholder immediately and fill
  in later via `tab_ctx.request_refresh()`, matching how Achievements loads.

## 8. Permissions and trust

Honest limit: plugins are GDScript running in the launcher process. Godot
cannot restrict what a loaded script does, so **permissions are a consent and
review mechanism, not enforcement**. The plan:

- Treat a plugin as **trusted code, equal to installing an application**. Say so
  in the install dialog.
- Show the manifest `permissions` and author before enabling; new or changed
  permissions disable the plugin until re-approved.
- Route all host API calls through permission checks, so a plugin that stays
  within the API is honest about what it uses. Raw access (for example calling
  `OS.execute` directly) cannot be prevented.
- Keep API-key style data (`secret` settings, RetroAchievements and
  SteamGridDB keys) **out of reach** of the API: plugins can ask Retrl to make
  a call using the user's key, but cannot read the key.
- Optional later: out-of-process plugins (a helper executable speaking JSON
  over stdio) for plugins that need real isolation.

Permission list (initial): `library.provide`, `library.modify`, `launch.hooks`,
`launch.run`, `process.spawn`, `fs.read:<scope>`, `fs.write:<scope>`,
`net.http:<host>`, `ui.menu`, `ui.game_tab`, `ui.settings`, `art.write`,
`apps.register`, `emulators.modify`, `achievements.read`, `input.hotkeys`.

## 9. Isolation and failure handling

- Every call into plugin code goes through one `PluginHost.safe_call()`.
  GDScript has no exceptions, so script errors cannot be caught; mitigate by
  validating returns, using timeouts for async work, and disabling a plugin
  that repeatedly returns invalid data.
- Plugin UI is mounted inside a host container with its own clip and error
  placeholder ("This tab failed to load. [Details] [Disable plugin]").
- A **crash guard**: if the previous run ended while a plugin was loading, the
  next start offers "Start without plugins".
- Registrations are tracked per plugin and removed on disable/unload.
- Per-plugin log and a **Plugins** screen in Settings (status, version,
  permissions, logs, enable/disable, update, remove).

## 10. Versioning and compatibility

- `api_version` integer; additive changes do not bump it, breaking ones do.
- Host keeps deprecated calls for at least one API version with a warning in the
  plugin log.
- The API is documented in `docs/plugin-api.md` and exposed as a typed
  `PluginContext` class so editors autocomplete it.
- A tiny `retrl-plugin-template` repo and a `plugin-dev` mode (hot reload,
  verbose logging, load from an arbitrary folder).

## 11. How the two planned plugins use it

**Gen1Recomp plugin**
- `library.add_source`: read the cart registry and `carts/*.g1rcart` in the
  game's data folder; return games with `launch` specs
  (`--game=… --cart=… --slot=…`).
- `add_game_tab("saves")`: slots, play time, backup/restore.
- `add_game_tab("box")`: read-only view of `box/storage.lua`.
- `launch.add_hooks`: back up saves before launch, warn if the game is open.
- `settings`: install location, data folder, portable mode, backup count.
- `credits`: the attribution line the Gen1Recomp licence requires.

**OpenHome plugin**
- `apps.register` (`tool`), a menu entry "Pokémon Box" that launches it, a
  game-tab action "Export save for OpenHome", and a save bridge that gathers
  `.sav` files into one folder.

## 12. Implementation phases

| Phase | Deliverable | Notes |
|---|---|---|
| 0 | **Spike**: confirm GDScript `load()`/`reload()` of `.gd` from `user://` in an exported build, and loading scenes from a `.pck` | Decides whether plugins may ship scenes or must build UI in code. |
| 1 | Registries: menu items, pages (`push_control`), dynamic game/recomp tab bar. Core tabs migrated. | No plugin loading yet; pure refactor with tests by hand. |
| 2 | Plugin host: discovery, manifest validation, lifecycle, `PluginContext` with `ui`, `log`, `storage`, `settings`. Plugins screen in Settings. | A "hello" plugin adds a menu page and a tab. |
| 3 | `library` sources (Quiver migrated), `launch` hooks, `process`, `fs`, `http`, events. | Enough for the Gen1Recomp plugin. |
| 4 | `apps` (tool mode), home rows, tile badges, game actions, art/screenshot/achievement services. | Enough for OpenHome plugin. |
| 5 | Install from zip/git release, update checks, permission prompts, plugin diagnostics. | |
| 6 | Docs, template repo, dev mode, typed context. | |

Phases 1 and 2 give the two things you asked for (menu tabs and game-detail
tabs). Phase 1 on its own is also a safe, user-visible-neutral cleanup.

## 13. Open questions

1. **Trust model**: is "plugins are trusted code, install only what you trust"
   acceptable, or do you want out-of-process plugins from day one?
2. **Plugin UI**: code-only UI (simplest, no scenes), or scenes via `.pck`
   (richer, depends on the spike)?
3. **Language**: GDScript only, or allow other runtimes later (for example
   Lua or an external helper)?
4. **Namespacing**: should plugin games be allowed to merge into existing
   platform tabs, or always live in their own?
5. **Retrl licence**: choose one before plugins start depending on it
   (relevant because Gen1Recomp and OpenHome are GPLv3).
