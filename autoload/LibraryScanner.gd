extends Node
## Owns the game library. If the user has configured any ROM directories
## (AppSettings -> Settings), those are scanned for real and used; if none
## are configured (or none match anything), it falls back to a bundled
## placeholder library (data/sample_library.json, fictional titles) so the
## UI always has something to show. Every game resolves its own emulator
## (+ a specific installed version, if the user picked one in GameSettings)
## here, so UI never has to ask "which emulator" - it only ever asks
## "which game".

const QuiverAdapter = preload("res://adapters/quiver_adapter.gd")

const SAMPLE_LIBRARY_PATH := "res://data/sample_library.json"
const OVERRIDES_PATH := "user://library_overrides.json"
const SETTINGS_PATH := "user://settings.json"

var games: Array[Dictionary] = []
var overrides: Dictionary = {}  # game_id -> {"emulator_id": .., "version": ..}
var _settings: Dictionary = {}

func _ready() -> void:
	reload()

func reload() -> void:
	games.clear()
	_load_settings()
	_load_overrides()

	var scanned := _scan_configured_directories()
	if not scanned.is_empty():
		games.append_array(scanned)
	else:
		_load_sample_library()

	for game in games:
		_apply_resolution(game)
	print("[LibraryScanner] loaded %d game(s) (%s)" % [games.size(), "scanned" if not scanned.is_empty() else "sample placeholder"])

func _load_sample_library() -> void:
	if not FileAccess.file_exists(SAMPLE_LIBRARY_PATH):
		push_warning("[LibraryScanner] no sample library found at %s" % SAMPLE_LIBRARY_PATH)
		return
	var file := FileAccess.open(SAMPLE_LIBRARY_PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed == null or not parsed.has("games"):
		push_error("[LibraryScanner] malformed sample library JSON")
		return
	for entry in parsed["games"]:
		games.append(entry as Dictionary)

func _load_overrides() -> void:
	overrides = {}
	if FileAccess.file_exists(OVERRIDES_PATH):
		var file := FileAccess.open(OVERRIDES_PATH, FileAccess.READ)
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		if typeof(parsed) == TYPE_DICTIONARY:
			overrides = parsed

func _save_overrides() -> void:
	var file := FileAccess.open(OVERRIDES_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(overrides))

func _load_settings() -> void:
	_settings = {"rom_directories": []}
	if FileAccess.file_exists(SETTINGS_PATH):
		var file := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		if typeof(parsed) == TYPE_DICTIONARY:
			_settings = parsed

func _save_settings() -> void:
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(_settings))

func rom_directories() -> Array:
	return _settings.get("rom_directories", [])

func add_rom_directory(platform_id: String, path: String) -> void:
	var dirs: Array = _settings.get("rom_directories", [])
	dirs.append({"platform_id": platform_id, "path": path})
	_settings["rom_directories"] = dirs
	_save_settings()
	reload()

func remove_rom_directory(index: int) -> void:
	var dirs: Array = _settings.get("rom_directories", [])
	if index >= 0 and index < dirs.size():
		dirs.remove_at(index)
		_settings["rom_directories"] = dirs
		_save_settings()
		reload()

func _scan_configured_directories() -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for entry in rom_directories():
		var platform_id: String = entry.get("platform_id", "")
		var dir_path: String = entry.get("path", "")
		var platform: Dictionary = EmulatorRegistry.get_platform(platform_id)
		if platform.is_empty():
			continue  # platform was deleted; directory stays configured but scans nothing
		if _uses_quiver_adapter(platform):
			found.append_array(QuiverAdapter.scan(dir_path, platform_id))
		else:
			found.append_array(_scan_dir(dir_path, platform_id, platform.get("extensions", [])))
	return found

## Quiver manages its own per-app subfolders rather than a flat folder of
## ROM files matched by extension (see adapters/quiver_adapter.gd). Which
## adapter scans a platform's directory is a separate question from which
## emulator launches its games by default - a recomp launches its own
## binary directly (default_emulator is null, see platforms.json), but its
## directory still needs Quiver's folder-layout-aware scan. Hence a
## dedicated "library_adapter" field on the platform instead of overloading
## default_emulator. Other library_adapter-style tools would need their own
## adapter the same way - there's no generic algorithm for "manages its own
## folder layout".
func _uses_quiver_adapter(platform: Dictionary) -> bool:
	return platform.get("library_adapter", "") == "quiver"

func _scan_dir(dir_path: String, platform_id: String, extensions: Array) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_warning("[LibraryScanner] cannot open ROM directory: %s" % dir_path)
		return found
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and (extensions.is_empty() or _matches_extension(file_name, extensions)):
			var full_path := dir_path.path_join(file_name)
			found.append({
				"id": full_path,
				"title": file_name.get_basename(),
				"platform_id": platform_id,
				"rom_path": full_path,
				"last_played": null,
				"playtime_hours": 0.0,
			})
		file_name = dir.get_next()
	dir.list_dir_end()
	return found

func _matches_extension(file_name: String, extensions: Array) -> bool:
	var ext := file_name.get_extension().to_lower()
	for allowed in extensions:
		if ext == String(allowed).to_lower():
			return true
	return false

## Each game's "title" is overwritten here - resolved, display-facing - so
## every screen (Home/Library/GameDetail/GameSettings) just reads `title`
## and never has to know whether it's a rename or the original scanned name.
## The original is kept in "scanned_title" so a rename can be reverted.
func _apply_resolution(game: Dictionary) -> void:
	var game_id: String = game.get("id", "")
	if not game.has("scanned_title"):
		game["scanned_title"] = game.get("title", "")
	var override: Dictionary = overrides.get(game_id, {})

	if override.has("emulator_id"):
		game["resolved_emulator_id"] = override["emulator_id"]
		game["resolved_version"] = override.get("version", null)
	else:
		game["resolved_emulator_id"] = _default_emulator_for(game)
		game["resolved_version"] = null

	var display_name: String = override.get("display_name", "")
	game["title"] = display_name if display_name != "" else game["scanned_title"]

	# A recorded play (actually launched through this app) always wins over
	# whatever the scan found (null for ROM files - nothing else tracks
	# this for them; Quiver's own LastPlayed.txt for recomps, which is
	# still a reasonable fallback until we've launched it ourselves).
	if override.has("last_played"):
		game["last_played"] = override["last_played"]

func _default_emulator_for(game: Dictionary) -> String:
	var platform: Dictionary = EmulatorRegistry.get_platform(game.get("platform_id", ""))
	var default_id: Variant = platform.get("default_emulator", null)
	return default_id if default_id != null else ""

## Pick a specific emulator (+ optionally a specific installed version) for
## this one game, overriding the platform default. Pass version="" to mean
## "whatever that emulator's active version is". Merges into any existing
## override (e.g. a rename) rather than replacing it outright.
func set_override(game_id: String, emulator_id: String, version: String) -> void:
	var entry: Dictionary = overrides.get(game_id, {})
	entry["emulator_id"] = emulator_id
	entry["version"] = version
	overrides[game_id] = entry
	_save_overrides()
	var game := get_game(game_id)
	if not game.is_empty():
		_apply_resolution(game)

## Renames a game for display only - never touches the ROM file/Quiver
## folder on disk. Pass "" (or all-whitespace) to revert to the original
## scanned name.
func set_display_name(game_id: String, name: String) -> void:
	var entry: Dictionary = overrides.get(game_id, {})
	var trimmed := name.strip_edges()
	if trimmed == "":
		entry.erase("display_name")
	else:
		entry["display_name"] = trimmed
	if entry.is_empty():
		overrides.erase(game_id)
	else:
		overrides[game_id] = entry
	_save_overrides()
	var game := get_game(game_id)
	if not game.is_empty():
		_apply_resolution(game)

## Call when a game is actually launched (LaunchManager.launch succeeded) -
## this is the only thing that makes Home's "Recent Games" ordering real for
## ROM-scanned games, since nothing else ever sets last_played for them.
func record_played(game_id: String) -> void:
	var entry: Dictionary = overrides.get(game_id, {})
	# space-separated, matching Quiver's own LastPlayed.txt format exactly -
	# both need to sort correctly together in games_by_recency().
	entry["last_played"] = Time.get_datetime_string_from_system(false, true)
	overrides[game_id] = entry
	_save_overrides()
	var game := get_game(game_id)
	if not game.is_empty():
		_apply_resolution(game)

func get_game(game_id: String) -> Dictionary:
	for game in games:
		if game.get("id", "") == game_id:
			return game
	return {}

func games_for_platform(platform_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for game in games:
		if game.get("platform_id", "") == platform_id:
			result.append(game)
	return result

## All games, most-recently-played first; never-played games last (in
## their original order), matching Steam's "Recent Games" row.
func games_by_recency() -> Array[Dictionary]:
	var played: Array[Dictionary] = []
	var unplayed: Array[Dictionary] = []
	for game in games:
		if game.get("last_played", null) != null:
			played.append(game)
		else:
			unplayed.append(game)
	played.sort_custom(func(a, b): return a["last_played"] > b["last_played"])
	played.append_array(unplayed)
	return played
