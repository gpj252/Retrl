extends Node
## Screenshots taken while a game/recomp is running, saved per game under
## their own folder - independent of whatever the emulator itself might or
## might not support, since there's no generic way to know an arbitrary
## user-defined emulator's own screenshot setting/path (same reasoning as
## why install folders are configured here rather than read from each
## emulator - see EmulatorRegistry.install_root_for).
##
## Godot has no "capture whatever's on screen right now" API of its own
## (it can only capture its own viewport, which is irrelevant here - the
## emulator's window is what's actually showing), so this shells out to a
## system screenshot tool, same Linux-only-target assumption already made
## for chmod/rm/tar elsewhere in this app. Tries, in order: `grim` (the
## natural fit for a bare wlroots/Wayland session), `spectacle` (KDE's
## tool, confirmed working for real on this machine - `spectacle -b -n -o
## <path>` captured a real screenshot, exit 0, valid PNG), then `scrot`
## (X11) as a last resort. Capture itself is confirmed; what ISN'T yet
## confirmed is whether the *hotkey* that triggers it still fires during
## actual gameplay (minimized, unfocused window) - see LaunchManager's
## screenshot-hotkey listener for that half of the question.

const CONFIG_PATH := "user://screenshots_config.json"
const TOOL_PREFERENCE := ["grim", "spectacle", "scrot"]

var _custom_dir: String = ""

func _ready() -> void:
	_load_config()

func _load_config() -> void:
	_custom_dir = ""
	if not FileAccess.file_exists(CONFIG_PATH):
		return
	var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) == TYPE_DICTIONARY:
		_custom_dir = parsed.get("screenshots_dir", "")

func _save_config() -> void:
	var file := FileAccess.open(CONFIG_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify({"screenshots_dir": _custom_dir}))

func default_screenshots_dir() -> String:
	return ProjectSettings.globalize_path("user://screenshots/")

func screenshots_dir() -> String:
	return _custom_dir if _custom_dir != "" else default_screenshots_dir()

## path == "" resets to the default - same convention as EmulatorRegistry's
## set_emulators_install_dir/set_recomps_install_dir.
func set_screenshots_dir(path: String) -> void:
	_custom_dir = path.strip_edges()
	_save_config()

## Screenshots are keyed the same way art is (ArtManager) - a game's real
## id (full ROM path) or "recomp:<id>" for a tracked recomp - hashed into a
## folder name since a raw game id isn't filesystem-safe on its own.
func _dir_for(screenshot_key: String) -> String:
	return screenshots_dir().path_join(screenshot_key.sha256_text())

## Takes a screenshot right now into this key's folder. Returns
## {"ok": bool, "message": String, "path": String}. screenshot_key == ""
## means "nothing identifiable is running" (see LaunchManager) - fails
## cleanly rather than saving somewhere with no game attached.
func capture(screenshot_key: String) -> Dictionary:
	if screenshot_key == "":
		return {"ok": false, "message": "Nothing to screenshot right now."}

	var dir_path := _dir_for(screenshot_key)
	DirAccess.make_dir_recursive_absolute(dir_path)
	var file_name := "%s.png" % Time.get_datetime_string_from_system(false, true).replace(":", "-").replace(" ", "_")
	var dest_path := dir_path.path_join(file_name)

	for tool_name in TOOL_PREFERENCE:
		if _try_capture(tool_name, dest_path):
			return {"ok": true, "message": "Screenshot saved.", "path": dest_path}
	return {"ok": false, "message": "No working screenshot tool found (tried: %s)." % ", ".join(TOOL_PREFERENCE)}

func _try_capture(tool_name: String, dest_path: String) -> bool:
	var globalized := ProjectSettings.globalize_path(dest_path)
	var args: PackedStringArray
	match tool_name:
		"grim":
			args = PackedStringArray([globalized])
		"spectacle":
			# -m (current monitor) instead of the -f (fullscreen/all-monitors)
			# default - confirmed necessary for real: on this machine's dual-
			# screen setup, the default captured both screens stitched into
			# one 5760x5373 image; -m captured just the current monitor
			# (1920x1080). "Current" means whichever monitor has the cursor,
			# not literally "whichever monitor the game is on" - there's no
			# simpler way to ask spectacle for that distinction, but the
			# cursor is the best available proxy.
			args = PackedStringArray(["-b", "-n", "-m", "-o", globalized])
		"scrot":
			args = PackedStringArray(["-o", globalized])
		_:
			return false
	var output: Array = []
	var exit_code := OS.execute(tool_name, args, output, true)
	return exit_code == 0 and FileAccess.file_exists(dest_path)

## Every screenshot for this key, newest first - for a GameDetail/
## RecompDetail "Screenshots" tab gallery.
func screenshots_for(screenshot_key: String) -> Array:
	var dir_path := _dir_for(screenshot_key)
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return []
	var found: Array = []
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.to_lower().ends_with(".png"):
			found.append(dir_path.path_join(file_name))
		file_name = dir.get_next()
	dir.list_dir_end()
	found.sort()
	found.reverse()
	return found

func delete_screenshot(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
