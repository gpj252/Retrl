extends Node
## Platforms and emulators are USER DATA, not fixed by us. The bundled
## res://data/ files are only a one-time seed on first run (so the app
## isn't empty on first launch); after that, everything lives in
## user://platforms.json / user://emulators.json and is fully editable
## (add/update/delete) from the Settings screen - nothing here is
## hardcoded as "the" platform/emulator list.
##
## Mutable install state (which versions are actually downloaded, which
## one is active, and - important - the actual filename of each installed
## version, since user-added local AppImages can be named anything) lives
## separately in user://emulator_state.json.

const SEED_PLATFORMS_PATH := "res://data/platforms.json"
const SEED_EMULATORS_DIR := "res://data/emulator_definitions/"
const USER_PLATFORMS_PATH := "user://platforms.json"
const USER_EMULATORS_PATH := "user://emulators.json"
const STATE_PATH := "user://emulator_state.json"
## Every bundled emulator_definitions id this install has ever seen, so a
## newly bundled entry (e.g. adding a new recomp like "top" in a later
## version of this launcher) reaches installs that were already seeded long
## ago too - not just fresh ones. One-way: an id in here is never re-added
## even if the user later deletes it, so "merge in new bundled entries"
## can't also mean "undo the user's deletions" on the next reload.
const SEED_IDS_SEEN_PATH := "user://emulator_seed_ids_seen.json"
## Where downloaded/installed files actually land, user-overridable from
## AppSettings → Emulators ("Emulators download folder" / "Recomps download
## folder"). Stores real absolute OS paths, not "user://..." ones, since a
## picked folder can be anywhere - see install_root_for.
const INSTALL_PATHS_PATH := "user://install_paths.json"

var platforms: Dictionary = {}   # id -> platform dict
var emulators: Dictionary = {}   # id -> emulator dict
var emulator_state: Dictionary = {}  # id -> {"installed": [version,...], "active": version, "binaries": {version: filename}}
var _install_paths: Dictionary = {}  # {"emulators_dir": String, "recomps_dir": String} - "" or missing means "use the default"

func _ready() -> void:
	_load_install_paths()
	reload()

func reload() -> void:
	_ensure_seeded()
	platforms = _read_json(USER_PLATFORMS_PATH)
	if typeof(platforms) != TYPE_DICTIONARY:
		platforms = {}
	emulators = _read_json(USER_EMULATORS_PATH)
	if typeof(emulators) != TYPE_DICTIONARY:
		emulators = {}
	_merge_new_bundled_emulators()
	_load_state()
	print("[EmulatorRegistry] loaded %d platform(s), %d emulator(s)" % [platforms.size(), emulators.size()])

func _ensure_seeded() -> void:
	if not FileAccess.file_exists(USER_PLATFORMS_PATH):
		var seed_data: Variant = _read_json(SEED_PLATFORMS_PATH)
		var seeded: Dictionary = {}
		if typeof(seed_data) == TYPE_DICTIONARY:
			for entry in seed_data.get("platforms", []):
				seeded[entry["id"]] = entry
		_write_json(USER_PLATFORMS_PATH, seeded)

	if not FileAccess.file_exists(USER_EMULATORS_PATH):
		var seeded_emulators: Dictionary = {}
		for data in _scan_bundled_emulator_definitions():
			seeded_emulators[data["id"]] = data
		_write_json(USER_EMULATORS_PATH, seeded_emulators)

func _scan_bundled_emulator_definitions() -> Array:
	var found: Array = []
	var dir := DirAccess.open(SEED_EMULATORS_DIR)
	if dir == null:
		return found
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			var data: Variant = _read_json(SEED_EMULATORS_DIR.path_join(file_name))
			if typeof(data) == TYPE_DICTIONARY and data.has("id"):
				found.append(data)
		file_name = dir.get_next()
	dir.list_dir_end()
	return found

## Adds any bundled definition whose id this install has never seen before
## (see SEED_IDS_SEEN_PATH) into the user's emulators.json - covers an
## install that was first seeded before a given bundled emulator/recomp
## existed. Never touches an id already known, so user edits/deletions of
## previously-seeded entries are left alone.
func _merge_new_bundled_emulators() -> void:
	var seen: Variant = _read_json(SEED_IDS_SEEN_PATH)
	var seen_ids: Dictionary = {}
	if typeof(seen) == TYPE_ARRAY:
		for id in seen:
			seen_ids[id] = true

	var emulators_changed := false
	for data in _scan_bundled_emulator_definitions():
		var id: String = data["id"]
		if seen_ids.has(id):
			continue
		seen_ids[id] = true
		if not emulators.has(id):
			emulators[id] = data
			emulators_changed = true

	if emulators_changed:
		_write_json(USER_EMULATORS_PATH, emulators)
	_write_json(SEED_IDS_SEEN_PATH, seen_ids.keys())

func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed == null:
		push_error("[EmulatorRegistry] malformed JSON: %s" % path)
	return parsed

func _write_json(path: String, data: Variant) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data, "  "))

func _load_state() -> void:
	emulator_state = {}
	if FileAccess.file_exists(STATE_PATH):
		var parsed: Variant = _read_json(STATE_PATH)
		if typeof(parsed) == TYPE_DICTIONARY:
			emulator_state = parsed

func _save_state() -> void:
	_write_json(STATE_PATH, emulator_state)

# --- lookups -----------------------------------------------------------

## Used by GameSettings to offer "which emulator should this ROM use" - a
## 'recomp' integration_mode entry (e.g. "top") isn't a ROM player at all,
## it's a standalone self-contained game that happens to live on the same
## platform, so it's excluded here even though it's still a real emulators
## entry everywhere else (EmulatorLibrary, EmulatorDetail, Home's updates
## row, Settings - none of those go through this function).
func emulators_for_platform(platform_id: String) -> Array:
	var result: Array = []
	for emulator_id in emulators:
		var emulator: Dictionary = emulators[emulator_id]
		if platform_id in emulator.get("platforms", []) and emulator.get("integration_mode", "emulator") != "recomp":
			result.append(emulator_id)
	return result

func get_platform(platform_id: String) -> Dictionary:
	return platforms.get(platform_id, {})

func get_emulator(emulator_id: String) -> Dictionary:
	return emulators.get(emulator_id, {})

func is_recomp(emulator_id: String) -> bool:
	return get_emulator(emulator_id).get("integration_mode", "emulator") == "recomp"

## Every 'recomp' integration_mode entry - self-contained native ports with
## no ROM, tracked via the same git-releases machinery as any emulator but
## presented to the user as games in their own "Recomps" library section
## (RecompLibrary/RecompDetail/RecompSettings) rather than mixed into
## Emulator Library or GameSettings' per-game emulator picker.
func recomp_ids() -> Array:
	var result: Array = []
	for emulator_id in emulators:
		if is_recomp(emulator_id):
			result.append(emulator_id)
	return result

# --- platform CRUD -------------------------------------------------------

## data needs: name, extensions (Array[String]), default_emulator (String or
## null), accent_color (optional "#rrggbb", auto-generated if omitted).
## Returns the new platform's id.
func add_platform(data: Dictionary) -> String:
	var id := _unique_id(data.get("name", "platform"), platforms)
	data["id"] = id
	if not data.has("accent_color") or data["accent_color"] == "":
		data["accent_color"] = _auto_accent_color(id)
	platforms[id] = data
	_write_json(USER_PLATFORMS_PATH, platforms)
	return id

func update_platform(platform_id: String, data: Dictionary) -> void:
	if not platforms.has(platform_id):
		return
	data["id"] = platform_id
	platforms[platform_id] = data
	_write_json(USER_PLATFORMS_PATH, platforms)

func delete_platform(platform_id: String) -> void:
	platforms.erase(platform_id)
	_write_json(USER_PLATFORMS_PATH, platforms)

# --- emulator CRUD -------------------------------------------------------

## data needs: name, platforms (Array[String] of platform ids it runs).
## Returns the new emulator's id.
func add_emulator(data: Dictionary) -> String:
	var id := _unique_id(data.get("name", "emulator"), emulators)
	data["id"] = id
	if not data.has("integration_mode"):
		data["integration_mode"] = "emulator"
	if not data.has("source"):
		data["source"] = {"type": "none"}
	if not data.has("launch"):
		data["launch"] = {"args_template": ["{rom_path}"]}
	emulators[id] = data
	_write_json(USER_EMULATORS_PATH, emulators)
	return id

func update_emulator(emulator_id: String, data: Dictionary) -> void:
	if not emulators.has(emulator_id):
		return
	data["id"] = emulator_id
	emulators[emulator_id] = data
	_write_json(USER_EMULATORS_PATH, emulators)

func delete_emulator(emulator_id: String) -> void:
	emulators.erase(emulator_id)
	_write_json(USER_EMULATORS_PATH, emulators)
	emulator_state.erase(emulator_id)
	_save_state()

func _unique_id(name: String, existing: Dictionary) -> String:
	var re := RegEx.new()
	re.compile("[^a-z0-9]+")
	var base: String = re.sub(name.to_lower().strip_edges(), "_", true).strip_edges()
	if base == "" or base == "_":
		base = "item"
	var candidate := base
	var suffix := 2
	while existing.has(candidate):
		candidate = "%s_%d" % [base, suffix]
		suffix += 1
	return candidate

func _auto_accent_color(seed_text: String) -> String:
	var hue := float(abs(seed_text.hash()) % 360) / 360.0
	var color := Color.from_hsv(hue, 0.55, 0.75)
	return "#" + color.to_html(false)

# --- installed version state ----------------------------------------------

## Records that a recomp was actually launched (RecompDetail's Play
## succeeded) - same idea as LibraryScanner.record_played for ROM-scanned
## games, but recomps aren't in LibraryScanner's game list at all, so this
## lives here instead, keyed into the same emulator_state entry that
## already tracks installed/active versions. No-ops if nothing's
## installed yet (no state entry to attach it to), which shouldn't happen
## in practice - Play is disabled until a version is active.
func record_played(emulator_id: String) -> void:
	if not emulator_state.has(emulator_id):
		return
	emulator_state[emulator_id]["last_played"] = Time.get_datetime_string_from_system(false, true)
	_save_state()

func last_played(emulator_id: String) -> Variant:
	return emulator_state.get(emulator_id, {}).get("last_played", null)

func installed_versions(emulator_id: String) -> Array:
	return emulator_state.get(emulator_id, {}).get("installed", [])

func is_version_installed(emulator_id: String, version: String) -> bool:
	return version in installed_versions(emulator_id)

## binary_filename is the actual file to run inside that version's install
## dir - installed versions can come from very differently-named downloads
## or user-added local files, so we record the real filename rather than
## assuming one.
func mark_version_installed(emulator_id: String, version: String, binary_filename: String) -> void:
	if not emulator_state.has(emulator_id):
		emulator_state[emulator_id] = {"installed": [], "active": null, "binaries": {}}
	var state: Dictionary = emulator_state[emulator_id]
	var installed: Array = state.get("installed", [])
	if version not in installed:
		installed.append(version)
	state["installed"] = installed
	var binaries: Dictionary = state.get("binaries", {})
	binaries[version] = binary_filename
	state["binaries"] = binaries
	if state.get("active", null) == null:
		state["active"] = version
	_save_state()

func set_active_version(emulator_id: String, version: String) -> void:
	if not emulator_state.has(emulator_id):
		return
	emulator_state[emulator_id]["active"] = version
	_save_state()

## Full path to the binary to execute for an installed version, or "" if
## that version isn't actually installed/recorded.
func version_binary_path(emulator_id: String, version: String) -> String:
	var filename: String = emulator_state.get(emulator_id, {}).get("binaries", {}).get(version, "")
	if filename == "":
		return ""
	return ProjectSettings.globalize_path(version_install_dir(emulator_id, version).path_join(filename))

## Where an installed version's files live on disk - under install_root_for,
## which is user-overridable (see AppSettings → Emulators).
func version_install_dir(emulator_id: String, version: String) -> String:
	return install_root_for(emulator_id).path_join(emulator_id).path_join(version)

# --- configurable install folders ------------------------------------------

func _load_install_paths() -> void:
	_install_paths = {}
	var parsed: Variant = _read_json(INSTALL_PATHS_PATH)
	if typeof(parsed) == TYPE_DICTIONARY:
		_install_paths = parsed

func _save_install_paths() -> void:
	_write_json(INSTALL_PATHS_PATH, _install_paths)

func default_emulators_install_dir() -> String:
	return ProjectSettings.globalize_path("user://emulators/")

## Deliberately its own default folder, not shared with emulators' - a
## recomp is presented to the user as a game, in its own "Recomps" section
## (RecompLibrary), so it gets its own default download location too, same
## as the rest of that split (RecompSettings' Versions tab vs GameSettings'
## Emulator tab, "emulator:<id>" vs "recomp:<id>" art keys, etc).
func default_recomps_install_dir() -> String:
	return ProjectSettings.globalize_path("user://recomps/")

func emulators_install_dir() -> String:
	var custom: String = _install_paths.get("emulators_dir", "")
	return custom if custom != "" else default_emulators_install_dir()

func recomps_install_dir() -> String:
	var custom: String = _install_paths.get("recomps_dir", "")
	return custom if custom != "" else default_recomps_install_dir()

## path == "" resets to the default (AppSettings' "Reset to Default").
## Doesn't move anything already installed under the old folder - only
## affects where *new* installs/updates land from here on.
func set_emulators_install_dir(path: String) -> void:
	_install_paths["emulators_dir"] = path.strip_edges()
	_save_install_paths()

func set_recomps_install_dir(path: String) -> void:
	_install_paths["recomps_dir"] = path.strip_edges()
	_save_install_paths()

## Single place that decides "emulators folder or recomps folder" for a
## given entry - UpdateManager's install/uninstall paths and this file's
## own version_install_dir all go through this rather than each re-checking
## is_recomp themselves.
func install_root_for(emulator_id: String) -> String:
	return recomps_install_dir() if is_recomp(emulator_id) else emulators_install_dir()

## Uninstalls a version: deletes its files on disk and drops it from state.
## If it was the active version, another installed version becomes active
## (arbitrary which one), or null if none are left.
func delete_installed_version(emulator_id: String, version: String) -> void:
	if not emulator_state.has(emulator_id):
		return
	var state: Dictionary = emulator_state[emulator_id]
	var installed: Array = state.get("installed", [])
	installed.erase(version)
	state["installed"] = installed
	var binaries: Dictionary = state.get("binaries", {})
	binaries.erase(version)
	state["binaries"] = binaries
	if state.get("active", null) == version:
		state["active"] = installed[0] if not installed.is_empty() else null
	_save_state()
	# rm -rf rather than a hand-rolled recursive DirAccess walk - this is a
	# Linux-only handheld target already (see UpdateManager's chmod +x calls),
	# and a version's install dir can contain nested folders from a zip
	# extraction (melonDS/Eden), not just the one binary.
	var dir_path := ProjectSettings.globalize_path(version_install_dir(emulator_id, version))
	if DirAccess.dir_exists_absolute(dir_path):
		OS.execute("rm", ["-rf", dir_path])
