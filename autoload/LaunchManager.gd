extends Node
## Actually launches a game: resolves the emulator binary (install dir +
## chosen/active version) and its args template from EmulatorRegistry, fills
## in {rom_path}/{version}, and starts it as a detached process. Games with
## no emulator (native/PC) launch their rom_path directly as the executable.
##
## Also supports launching just the emulator by itself, either for a game's
## assigned emulator (launch_emulator_only - no ROM, so the user can reach
## the emulator's own settings/config UI without having to load a game
## first) or completely standalone by emulator id (launch_emulator_standalone
## - used by the Emulator Library page, which has no "current game" to
## resolve from).
##
## Every failure path returns a specific reason instead of silently doing
## nothing - "no version installed", "binary not found on disk", etc. -
## since this is the piece every other screen has been calling a stub.
##
## Tracks the single running process (poll-based, since Godot has no child-
## exit signal) and refuses a second concurrent launch while one is active -
## confirmed necessary for real: SteamOS gamemode was observed leaving the
## launcher's own UI interactive while an emulator ran (controller input
## kept navigating/selecting here instead of the game), which could fire
## Play again and land two games running at once. game_started/game_stopped
## let Shell pause input and yield window focus for the duration; this guard
## is the hard stop regardless of whether that actually reaches the
## compositor in a given gamescope session.
##
## Also owns the screenshot hotkey (see _unhandled_input below) - this node
## is already PROCESS_MODE_ALWAYS for the poll timer's sake, which is
## exactly what lets one specific input combo keep working while Shell has
## paused everything else for the "playing" state. Whether that combo's
## *events* even reach this node while the window is minimized/unfocused is
## a separate, unconfirmed question - see the comment on _unhandled_input.

signal game_started(label: String)
signal game_stopped()
signal screenshot_captured(ok: bool, message: String)

const EXIT_POLL_INTERVAL_SECONDS := 1.0

var _running_pid: int = -1
var _poll_timer: Timer
var _screenshot_key: String = ""

func _ready() -> void:
	# Must keep polling (and Shell must keep un-pausing) even while the rest
	# of the tree is paused for the "playing" state below - PROCESS_MODE_
	# ALWAYS is what makes that possible.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_poll_timer = Timer.new()
	_poll_timer.wait_time = EXIT_POLL_INTERVAL_SECONDS
	_poll_timer.process_mode = Node.PROCESS_MODE_ALWAYS
	_poll_timer.timeout.connect(_check_running_process)
	add_child(_poll_timer)

func is_game_running() -> bool:
	return _running_pid > 0

## screenshot_key identifies which game/recomp a screenshot taken during
## this run should be filed under (ArtManager-style: a game's real id, or
## "recomp:<id>" - see RecompDetail/GameDetail). "" means "don't know/not
## applicable" (e.g. opening just an emulator's own UI with no game loaded)
## - the hotkey below silently no-ops rather than saving somewhere with no
## game attached.
func launch(game: Dictionary) -> Dictionary:
	if is_game_running():
		return _fail("A game is already running — close it before launching another.")

	var emulator_id: String = game.get("resolved_emulator_id", "")
	var rom_path: String = game.get("rom_path", "")

	if emulator_id == "":
		if rom_path == "":
			return _fail("No ROM/executable path set for this game.")
		return _run(rom_path, [], game.get("title", "Game"), game.get("id", ""))

	var resolved := _resolve_emulator_binary(emulator_id, game.get("resolved_version", null))
	if not resolved.get("ok", false):
		return resolved

	var launch_def: Dictionary = resolved["emulator"].get("launch", {})
	var args: Array = []
	for raw_arg in launch_def.get("args_template", []):
		args.append(String(raw_arg).replace("{rom_path}", rom_path).replace("{version}", resolved["version"]))

	return _run(resolved["binary_path"], args, game.get("title", "Game"), game.get("id", ""))

## Starts the assigned emulator on its own, with no ROM/game argument - for
## reaching its own settings/config screen (controller bindings, video
## options, BIOS paths, etc) without loading a specific game first.
func launch_emulator_only(game: Dictionary) -> Dictionary:
	if is_game_running():
		return _fail("A game is already running — close it before opening an emulator.")

	var emulator_id: String = game.get("resolved_emulator_id", "")
	if emulator_id == "":
		return _fail("This game runs natively - there's no separate emulator to open.")

	var resolved := _resolve_emulator_binary(emulator_id, game.get("resolved_version", null))
	if not resolved.get("ok", false):
		return resolved

	var launch_def: Dictionary = resolved["emulator"].get("launch", {})
	var args := _build_no_rom_args(launch_def, resolved["version"])
	return _run(resolved["binary_path"], args, resolved["emulator"].get("name", emulator_id))

## Same as launch_emulator_only, but by emulator id directly rather than a
## game dict - used both by the Emulator Library page (opening/trying an
## emulator with no game involved at all - screenshot_key stays "" there)
## and by RecompDetail's Play button (a recomp IS the game it plays, so
## RecompDetail passes "recomp:<id>" as screenshot_key). version defaults
## to that emulator's active install if omitted.
func launch_emulator_standalone(emulator_id: String, version: Variant = null, screenshot_key: String = "") -> Dictionary:
	if is_game_running():
		return _fail("A game is already running — close it before opening an emulator.")

	var resolved := _resolve_emulator_binary(emulator_id, version)
	if not resolved.get("ok", false):
		return resolved

	var launch_def: Dictionary = resolved["emulator"].get("launch", {})
	var args := _build_no_rom_args(launch_def, resolved["version"])
	return _run(resolved["binary_path"], args, resolved["emulator"].get("name", emulator_id), screenshot_key)

## Args that only make sense with a ROM ({rom_path}) are dropped rather than
## passed through unsubstituted - most emulators just open their normal UI
## with zero args. A flag immediately preceding a bare "{rom_path}" token
## (e.g. ["-g", "{rom_path}"]) is dropped along with it, not left dangling
## with no value - confirmed necessary for real: the user's eden entry is
## ["-f", "-g", "{rom_path}"], and a bare "-g" with nothing after it would
## likely just error. A combined token like "--rom={rom_path}" is self-
## contained, so it's dropped on its own without touching the preceding arg.
func _build_no_rom_args(launch_def: Dictionary, version: String) -> Array:
	var args: Array = []
	for raw_arg in launch_def.get("args_template", []):
		var text := String(raw_arg)
		if text.find("{rom_path}") != -1:
			if text.strip_edges() == "{rom_path}" and not args.is_empty() and String(args[-1]).begins_with("-"):
				args.pop_back()
			continue
		args.append(text.replace("{version}", version))
	return args

## Shared resolution for every entry point above. version_override null
## means "use whatever's active for this emulator". Returns either
## {"ok": true, "emulator": Dictionary, "version": String, "binary_path": String}
## or a {"ok": false, "message": String} failure dict.
func _resolve_emulator_binary(emulator_id: String, version_override: Variant = null) -> Dictionary:
	var emulator: Dictionary = EmulatorRegistry.get_emulator(emulator_id)
	if emulator.is_empty():
		return _fail("Unknown emulator '%s'." % emulator_id)

	var version: Variant = version_override
	if version == null:
		version = EmulatorRegistry.emulator_state.get(emulator_id, {}).get("active", null)
	if version == null:
		return _fail("No version of %s installed yet — pick one from the gear icon." % emulator.get("name", emulator_id))

	var binary_path: String = EmulatorRegistry.version_binary_path(emulator_id, version)
	if binary_path == "" or not FileAccess.file_exists(binary_path):
		return _fail("Emulator binary not found for %s version '%s' — the install may have failed." % [emulator.get("name", emulator_id), version])

	return {"ok": true, "emulator": emulator, "version": version, "binary_path": binary_path}

func _run(binary_path: String, args: Array, label: String, screenshot_key: String = "") -> Dictionary:
	var pid := OS.create_process(binary_path, args)
	if pid <= 0:
		return _fail("Failed to start process: %s" % binary_path)
	_running_pid = pid
	_screenshot_key = screenshot_key
	_poll_timer.start()
	game_started.emit(label)
	return {"ok": true, "message": "Launched (pid %d)" % pid, "pid": pid}

func _check_running_process() -> void:
	if _running_pid <= 0:
		_poll_timer.stop()
		return
	if OS.is_process_running(_running_pid):
		return
	_running_pid = -1
	_screenshot_key = ""
	_poll_timer.stop()
	game_stopped.emit()

func _fail(message: String) -> Dictionary:
	push_warning("[LaunchManager] %s" % message)
	return {"ok": false, "message": message}

## Screenshot hotkey: Select/Back held + Y/Triangle pressed (controller),
## or F12 (keyboard, mainly useful testing from the editor). This node is
## PROCESS_MODE_ALWAYS, so Godot keeps calling this even while Shell has
## get_tree().paused = true for the "playing" state - that part is
## guaranteed. What ISN'T guaranteed: whether the event even reaches here
## at all while the window is minimized/unfocused during actual gameplay.
## Keyboard almost certainly won't (keyboard focus is strictly one-window-
## at-a-time on basically every compositor) - controller input has a real
## chance, since Godot's Linux joypad backend reads raw evdev device nodes
## directly rather than through window-focus-gated input messages, but
## that's a real-hardware question, not something provable from code.
## Silently no-ops if no game is running or it has no screenshot_key (e.g.
## an emulator opened standalone with no game loaded).
func _unhandled_input(event: InputEvent) -> void:
	if not is_game_running() or _screenshot_key == "":
		return

	var triggered := false
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F12:
		triggered = true
	elif event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_Y:
		if Input.is_joy_button_pressed(event.device, JOY_BUTTON_BACK):
			triggered = true

	if not triggered:
		return
	get_viewport().set_input_as_handled()
	_take_screenshot()

func _take_screenshot() -> void:
	var result: Dictionary = ScreenshotManager.capture(_screenshot_key)
	screenshot_captured.emit(result.get("ok", false), result.get("message", ""))
