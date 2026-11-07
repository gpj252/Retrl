extends Control
## App-wide settings: three tabs.
## - Directories: ROM/install folders that feed LibraryScanner's real scan.
## - Platforms: fully user-defined (name, extensions, default emulator) -
##   nothing is hardcoded here, the bundled data/platforms.json is only a
##   one-time seed (see EmulatorRegistry).
## - Emulators: user-defined too (name + which platforms it belongs to).
##   Every emulator row - bundled or user-created - has its own editable
##   repo URL + asset pattern ("Save Repo"): point any emulator at any git
##   host (GitHub or a self-hosted Gitea/Forgejo instance), not just the
##   ones we happened to bundle. Also where a local .AppImage gets added as
##   an installed "release" directly (no network needed) for instant use.
##
## Add-only for Platforms for now - no edit form yet, delete + recreate if
## you need to change one (Emulators got a real edit path via the repo row
## above; Platforms haven't needed it as urgently yet).

const INACTIVE_COLOR := Color(0.6, 0.65, 0.7, 1)
const ACTIVE_COLOR := Color.WHITE
const FEEDBACK_COLOR := Color(0.5, 0.75, 0.95, 1)
const ERROR_COLOR := Color(0.9, 0.45, 0.45, 1)

@onready var directories_tab_button: Button = %DirectoriesTabButton
@onready var platforms_tab_button: Button = %PlatformsTabButton
@onready var emulators_tab_button: Button = %EmulatorsTabButton
@onready var recomps_tab_button: Button = %RecompsTabButton
@onready var art_tab_button: Button = %ArtTabButton
@onready var directories_pane: VBoxContainer = %DirectoriesPane
@onready var platforms_pane: VBoxContainer = %PlatformsPane
@onready var emulators_pane: VBoxContainer = %EmulatorsPane
@onready var recomps_pane: VBoxContainer = %RecompsPane
@onready var art_pane: VBoxContainer = %ArtPane

# Directories tab widgets (built once, list rebuilt on change)
var _dir_platform_option: OptionButton
var _dir_path_edit: LineEdit
var _dir_feedback: Label
var _dirs_list: VBoxContainer
var _dir_platform_ids: Array = []

# Platforms tab widgets
var _platforms_list: VBoxContainer
var _platform_form: VBoxContainer
var _platform_name_edit: LineEdit
var _platform_ext_edit: LineEdit
var _platform_default_option: OptionButton
var _platform_default_ids: Array = []
var _platform_feedback: Label

# Emulators tab widgets
var _emulators_list: VBoxContainer
var _emulator_form: VBoxContainer
var _emulator_name_edit: LineEdit
var _emulator_repo_edit: LineEdit
var _emulator_platform_checks: Dictionary = {}  # platform_id -> CheckBox
var _emulator_feedback: Label
var _update_check_label: Label

# Recomps tab widgets - separate from Emulators' (see "Recomps" section
# below), even though both ultimately call EmulatorRegistry.add_emulator.
var _recomps_list: VBoxContainer
var _recomp_form: VBoxContainer
var _recomp_name_edit: LineEdit
var _recomp_repo_edit: LineEdit
var _recomp_platform_checks: Dictionary = {}  # platform_id -> CheckBox
var _recomp_feedback: Label

func _ready() -> void:
	var shell := get_tree().get_first_node_in_group("shell")
	if shell:
		shell.set_title("Settings")

	directories_tab_button.pressed.connect(func(): _show_tab("directories"))
	platforms_tab_button.pressed.connect(func(): _show_tab("platforms"))
	emulators_tab_button.pressed.connect(func(): _show_tab("emulators"))
	recomps_tab_button.pressed.connect(func(): _show_tab("recomps"))
	art_tab_button.pressed.connect(func(): _show_tab("art"))

	_build_directories_pane()
	_build_platforms_pane()
	_build_emulators_pane()
	_build_recomps_pane()
	_build_art_pane()
	_show_tab("directories")

	directories_tab_button.grab_focus()

func _show_tab(tab: String) -> void:
	directories_pane.visible = tab == "directories"
	platforms_pane.visible = tab == "platforms"
	emulators_pane.visible = tab == "emulators"
	recomps_pane.visible = tab == "recomps"
	art_pane.visible = tab == "art"
	directories_tab_button.add_theme_color_override("font_color", ACTIVE_COLOR if tab == "directories" else INACTIVE_COLOR)
	platforms_tab_button.add_theme_color_override("font_color", ACTIVE_COLOR if tab == "platforms" else INACTIVE_COLOR)
	emulators_tab_button.add_theme_color_override("font_color", ACTIVE_COLOR if tab == "emulators" else INACTIVE_COLOR)
	recomps_tab_button.add_theme_color_override("font_color", ACTIVE_COLOR if tab == "recomps" else INACTIVE_COLOR)
	art_tab_button.add_theme_color_override("font_color", ACTIVE_COLOR if tab == "art" else INACTIVE_COLOR)
	# Toggling .visible alone left focus on the sidebar tab button just
	# pressed, with nothing inside ContentScroll for a controller to land
	# on - follow_focus (see AppSettings.tscn) then had nothing to scroll
	# to. Same bug/fix as GameSettings._show_tab.
	var pane := directories_pane
	if tab == "platforms":
		pane = platforms_pane
	elif tab == "emulators":
		pane = emulators_pane
	elif tab == "recomps":
		pane = recomps_pane
	elif tab == "art":
		pane = art_pane
	_grab_first_focusable(pane)

## Depth-first search for the first visible, focusable control under
## `root` - see _show_tab.
func _grab_first_focusable(root: Control) -> void:
	var found := _find_first_focusable(root)
	if found != null:
		found.grab_focus()

func _find_first_focusable(node: Node) -> Control:
	for child in node.get_children():
		if child is Control:
			var control: Control = child
			if not control.visible:
				continue
			if control.focus_mode != Control.FOCUS_NONE:
				return control
			var nested := _find_first_focusable(control)
			if nested != null:
				return nested
	return null

## Adds a "Browse..." button to `row` that opens a real system file/folder
## picker (FileDialog) and writes the chosen path into `edit`'s text - every
## path field in this screen (ROM directories, local .AppImage, the two
## install-folder settings below) gets one of these rather than being a
## plain text field to type a path into blind. The field itself stays fully
## editable too - typing/pasting a path directly still works, this is
## additive, not a replacement.
func _add_browse_button(row: HBoxContainer, edit: LineEdit, file_mode: FileDialog.FileMode, filter: String = "", filter_description: String = "") -> void:
	var browse_button := Button.new()
	browse_button.text = "Browse..."
	row.add_child(browse_button)
	browse_button.pressed.connect(func():
		var dialog := FileDialog.new()
		dialog.access = FileDialog.ACCESS_FILESYSTEM
		dialog.file_mode = file_mode
		if filter != "":
			dialog.add_filter(filter, filter_description)
		dialog.size = Vector2i(900, 600)
		var current := edit.text.strip_edges()
		if current != "":
			# A file field's current text is the file itself; a folder
			# field's is the folder - DirAccess.dir_exists_absolute tells
			# which, so this works for both without the caller specifying.
			dialog.current_dir = current if DirAccess.dir_exists_absolute(current) else current.get_base_dir()
		add_child(dialog)
		dialog.dir_selected.connect(func(path: String):
			edit.text = path
			dialog.queue_free()
		)
		dialog.file_selected.connect(func(path: String):
			edit.text = path
			dialog.queue_free()
		)
		dialog.canceled.connect(func(): dialog.queue_free())
		dialog.popup_centered()
	)

## One row of "Emulators download folder" / "Recomps download folder" -
## defaults as-is (EmulatorRegistry.default_*_install_dir, under this app's
## own user:// data dir) unless the user picks something else here. Doesn't
## move anything already installed under the previous folder - only new
## installs/updates from here on land in the new one.
func _build_install_dir_row(parent: VBoxContainer, title: String, current_value: String, default_value: String, setter: Callable) -> void:
	var label := Label.new()
	label.text = title
	parent.add_child(label)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)

	var edit := LineEdit.new()
	edit.text = current_value
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(edit)
	_add_browse_button(row, edit, FileDialog.FILE_MODE_OPEN_DIR)

	var save_button := Button.new()
	save_button.text = "Save"
	row.add_child(save_button)

	var reset_button := Button.new()
	reset_button.text = "Reset to Default"
	row.add_child(reset_button)

	var feedback := Label.new()
	feedback.add_theme_color_override("font_color", FEEDBACK_COLOR)
	parent.add_child(feedback)

	save_button.pressed.connect(func():
		var path := edit.text.strip_edges()
		if path == "":
			feedback.text = "Give it a folder path, or use Reset to Default."
			feedback.add_theme_color_override("font_color", ERROR_COLOR)
			return
		setter.call(path)
		feedback.text = "Saved - new installs/updates will go here. Anything already installed stays where it was."
		feedback.add_theme_color_override("font_color", FEEDBACK_COLOR)
	)
	reset_button.pressed.connect(func():
		setter.call("")
		edit.text = default_value
		feedback.text = "Reset to default."
		feedback.add_theme_color_override("font_color", FEEDBACK_COLOR)
	)

# ======================== Directories ========================

func _build_directories_pane() -> void:
	var hint := Label.new()
	hint.text = "Point the launcher at a folder for a platform; matching files become library entries."
	hint.add_theme_color_override("font_color", INACTIVE_COLOR)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	directories_pane.add_child(hint)

	var add_row := HBoxContainer.new()
	add_row.add_theme_constant_override("separation", 12)
	directories_pane.add_child(add_row)

	_dir_platform_option = OptionButton.new()
	_dir_platform_option.custom_minimum_size = Vector2(200, 0)
	add_row.add_child(_dir_platform_option)

	_dir_path_edit = LineEdit.new()
	_dir_path_edit.placeholder_text = "/home/you/ROMs/n64"
	_dir_path_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_row.add_child(_dir_path_edit)
	_add_browse_button(add_row, _dir_path_edit, FileDialog.FILE_MODE_OPEN_DIR)

	var add_button := Button.new()
	add_button.text = "Add Directory"
	add_button.pressed.connect(_on_add_directory_pressed)
	add_row.add_child(add_button)

	_dir_feedback = Label.new()
	_dir_feedback.add_theme_color_override("font_color", FEEDBACK_COLOR)
	directories_pane.add_child(_dir_feedback)

	directories_pane.add_child(HSeparator.new())

	_dirs_list = VBoxContainer.new()
	_dirs_list.add_theme_constant_override("separation", 8)
	directories_pane.add_child(_dirs_list)

	_refresh_directories_tab()

func _refresh_directories_tab() -> void:
	_dir_platform_option.clear()
	_dir_platform_ids.clear()
	for platform_id in EmulatorRegistry.platforms:
		var platform: Dictionary = EmulatorRegistry.get_platform(platform_id)
		_dir_platform_option.add_item(platform.get("name", platform_id))
		_dir_platform_ids.append(platform_id)

	for child in _dirs_list.get_children():
		child.queue_free()

	var dirs := LibraryScanner.rom_directories()
	if dirs.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No directories configured yet — using the bundled placeholder library below."
		empty_label.add_theme_color_override("font_color", INACTIVE_COLOR)
		_dirs_list.add_child(empty_label)
		return

	for i in dirs.size():
		var entry: Dictionary = dirs[i]
		var platform: Dictionary = EmulatorRegistry.get_platform(entry.get("platform_id", ""))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)

		var label := Label.new()
		var platform_name: String = platform.get("name", entry.get("platform_id", "?") + " (deleted platform)")
		label.text = "[%s]  %s" % [platform_name, entry.get("path", "")]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)

		var remove_button := Button.new()
		remove_button.text = "Remove"
		remove_button.pressed.connect(_on_remove_directory_pressed.bind(i))
		row.add_child(remove_button)

		_dirs_list.add_child(row)

func _on_add_directory_pressed() -> void:
	var path := _dir_path_edit.text.strip_edges()
	if path == "":
		_dir_feedback.text = "Enter a directory path first."
		return
	if not DirAccess.dir_exists_absolute(path):
		_dir_feedback.text = "That path doesn't exist or isn't readable: %s" % path
		return
	var index := _dir_platform_option.selected
	if index < 0 or index >= _dir_platform_ids.size():
		_dir_feedback.text = "Pick a platform first."
		return

	LibraryScanner.add_rom_directory(_dir_platform_ids[index], path)
	_dir_path_edit.text = ""
	_dir_feedback.text = "Added. Library now has %d game(s) total." % LibraryScanner.games.size()
	_refresh_directories_tab()

func _on_remove_directory_pressed(index: int) -> void:
	LibraryScanner.remove_rom_directory(index)
	_dir_feedback.text = "Removed. Library now has %d game(s) total." % LibraryScanner.games.size()
	_refresh_directories_tab()

# ======================== Platforms ========================

func _build_platforms_pane() -> void:
	var hint := Label.new()
	hint.text = "Platforms are yours to define — name it, say which file extensions belong to it, and which emulator should run it by default."
	hint.add_theme_color_override("font_color", INACTIVE_COLOR)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	platforms_pane.add_child(hint)

	var toggle_button := Button.new()
	toggle_button.text = "+ Add Platform"
	platforms_pane.add_child(toggle_button)

	_platform_form = VBoxContainer.new()
	_platform_form.visible = false
	_platform_form.add_theme_constant_override("separation", 8)
	platforms_pane.add_child(_platform_form)

	toggle_button.pressed.connect(func():
		_platform_form.visible = not _platform_form.visible
		if _platform_form.visible:
			_refresh_platform_form_options()
	)

	_platform_name_edit = LineEdit.new()
	_platform_name_edit.placeholder_text = "Platform name (e.g. Nintendo Switch 2)"
	_platform_form.add_child(_platform_name_edit)

	_platform_ext_edit = LineEdit.new()
	_platform_ext_edit.placeholder_text = "File extensions, comma separated (e.g. nup, nsp)"
	_platform_form.add_child(_platform_ext_edit)

	var default_row := HBoxContainer.new()
	default_row.add_theme_constant_override("separation", 12)
	_platform_form.add_child(default_row)
	var default_label := Label.new()
	default_label.text = "Default emulator:"
	default_row.add_child(default_label)
	_platform_default_option = OptionButton.new()
	_platform_default_option.custom_minimum_size = Vector2(200, 0)
	default_row.add_child(_platform_default_option)

	var save_button := Button.new()
	save_button.text = "Save Platform"
	save_button.pressed.connect(_on_save_platform_pressed)
	_platform_form.add_child(save_button)

	_platform_feedback = Label.new()
	_platform_feedback.add_theme_color_override("font_color", FEEDBACK_COLOR)
	_platform_form.add_child(_platform_feedback)

	platforms_pane.add_child(HSeparator.new())

	_platforms_list = VBoxContainer.new()
	_platforms_list.add_theme_constant_override("separation", 8)
	platforms_pane.add_child(_platforms_list)

	_refresh_platforms_tab()

func _refresh_platform_form_options() -> void:
	_platform_default_option.clear()
	_platform_default_ids.clear()
	_platform_default_option.add_item("None (native, no emulator)")
	_platform_default_ids.append("")
	for emulator_id in EmulatorRegistry.emulators:
		var emulator: Dictionary = EmulatorRegistry.get_emulator(emulator_id)
		_platform_default_option.add_item(emulator.get("name", emulator_id))
		_platform_default_ids.append(emulator_id)

func _on_save_platform_pressed() -> void:
	var name := _platform_name_edit.text.strip_edges()
	if name == "":
		_platform_feedback.text = "Give the platform a name."
		_platform_feedback.add_theme_color_override("font_color", ERROR_COLOR)
		return
	var extensions: Array = []
	for raw in _platform_ext_edit.text.split(","):
		var ext := raw.strip_edges().to_lower().trim_prefix(".")
		if ext != "":
			extensions.append(ext)

	var default_index := _platform_default_option.selected
	var default_emulator: Variant = null
	if default_index >= 0 and default_index < _platform_default_ids.size() and _platform_default_ids[default_index] != "":
		default_emulator = _platform_default_ids[default_index]

	var id: String = EmulatorRegistry.add_platform({
		"name": name,
		"extensions": extensions,
		"default_emulator": default_emulator,
	})

	_platform_name_edit.text = ""
	_platform_ext_edit.text = ""
	_platform_form.visible = false
	_platform_feedback.text = ""
	LibraryScanner.reload()
	_refresh_platforms_tab()
	_refresh_directories_tab()

func _refresh_platforms_tab() -> void:
	for child in _platforms_list.get_children():
		child.queue_free()

	if EmulatorRegistry.platforms.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No platforms yet."
		empty_label.add_theme_color_override("font_color", INACTIVE_COLOR)
		_platforms_list.add_child(empty_label)
		return

	for platform_id in EmulatorRegistry.platforms:
		var platform: Dictionary = EmulatorRegistry.get_platform(platform_id)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)

		var default_id: Variant = platform.get("default_emulator", null)
		var default_name := "native"
		if default_id != null:
			default_name = EmulatorRegistry.get_emulator(default_id).get("name", default_id)
		var extensions: Array = platform.get("extensions", [])
		var ext_text := ", ".join(extensions) if not extensions.is_empty() else "(any file)"

		var label := Label.new()
		label.text = "%s — .%s — default: %s" % [platform.get("name", platform_id), ext_text.replace(", ", ", ."), default_name]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)

		var delete_button := Button.new()
		delete_button.text = "Delete"
		delete_button.pressed.connect(_on_delete_platform_pressed.bind(platform_id))
		row.add_child(delete_button)

		_platforms_list.add_child(row)

func _on_delete_platform_pressed(platform_id: String) -> void:
	EmulatorRegistry.delete_platform(platform_id)
	LibraryScanner.reload()
	_refresh_platforms_tab()
	_refresh_directories_tab()

# ======================== Emulators ========================

func _build_emulators_pane() -> void:
	var hint := Label.new()
	hint.text = "Emulators are yours to define too — name it and mark which platform(s) it belongs to. Add a local .AppImage below to make it launchable right away, no download needed. (Recomps have their own tab now - see Recomps.)"
	hint.add_theme_color_override("font_color", INACTIVE_COLOR)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	emulators_pane.add_child(hint)

	_build_install_dir_row(
		emulators_pane,
		"Emulators download folder",
		EmulatorRegistry.emulators_install_dir(),
		EmulatorRegistry.default_emulators_install_dir(),
		Callable(EmulatorRegistry, "set_emulators_install_dir"),
	)
	emulators_pane.add_child(HSeparator.new())

	# Manual override for UpdateManager's once-a-day auto-check (see Home.gd
	# and UpdateManager.startup_check_for_updates) - GitHub's unauthenticated
	# rate limit got burned through fast when every Home visit re-checked
	# every emulator, so the automatic check is now heavily throttled; this
	# is the escape hatch for "no really, check right now".
	var check_row := HBoxContainer.new()
	check_row.add_theme_constant_override("separation", 12)
	emulators_pane.add_child(check_row)

	_update_check_label = Label.new()
	_update_check_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	check_row.add_child(_update_check_label)

	var check_now_button := Button.new()
	check_now_button.text = "Check for Updates Now"
	check_row.add_child(check_now_button)
	_refresh_update_check_label()

	check_now_button.pressed.connect(func():
		check_now_button.disabled = true
		check_now_button.text = "Checking..."
		await UpdateManager.force_check_for_updates()
		_refresh_update_check_label()
		if is_instance_valid(check_now_button):
			check_now_button.disabled = false
			check_now_button.text = "Check for Updates Now"
	)

	emulators_pane.add_child(HSeparator.new())

	var toggle_button := Button.new()
	toggle_button.text = "+ Add Emulator"
	emulators_pane.add_child(toggle_button)

	_emulator_form = VBoxContainer.new()
	_emulator_form.visible = false
	_emulator_form.add_theme_constant_override("separation", 8)
	emulators_pane.add_child(_emulator_form)

	toggle_button.pressed.connect(func():
		_emulator_form.visible = not _emulator_form.visible
		if _emulator_form.visible:
			_rebuild_emulator_form_checks()
	)

	_emulator_name_edit = LineEdit.new()
	_emulator_name_edit.placeholder_text = "Emulator name (e.g. Eden)"
	_emulator_form.add_child(_emulator_name_edit)

	_emulator_repo_edit = LineEdit.new()
	_emulator_repo_edit.placeholder_text = "Repo URL (optional, any git host - e.g. https://github.com/owner/repo) - can add/change this later too"
	_emulator_form.add_child(_emulator_repo_edit)

	var checks_label := Label.new()
	checks_label.text = "Runs these platforms:"
	_emulator_form.add_child(checks_label)

	_emulator_checks_container = VBoxContainer.new()
	_emulator_form.add_child(_emulator_checks_container)

	var save_button := Button.new()
	save_button.text = "Save Emulator"
	save_button.pressed.connect(_on_save_emulator_pressed)
	_emulator_form.add_child(save_button)

	_emulator_feedback = Label.new()
	_emulator_feedback.add_theme_color_override("font_color", FEEDBACK_COLOR)
	_emulator_form.add_child(_emulator_feedback)

	emulators_pane.add_child(HSeparator.new())

	_emulators_list = VBoxContainer.new()
	_emulators_list.add_theme_constant_override("separation", 16)
	emulators_pane.add_child(_emulators_list)

	_refresh_emulators_tab()

var _emulator_checks_container: VBoxContainer

func _rebuild_emulator_form_checks() -> void:
	for child in _emulator_checks_container.get_children():
		child.queue_free()
	_emulator_platform_checks.clear()
	for platform_id in EmulatorRegistry.platforms:
		var platform: Dictionary = EmulatorRegistry.get_platform(platform_id)
		var check := CheckBox.new()
		check.text = platform.get("name", platform_id)
		_emulator_checks_container.add_child(check)
		_emulator_platform_checks[platform_id] = check

func _on_save_emulator_pressed() -> void:
	var name := _emulator_name_edit.text.strip_edges()
	if name == "":
		_emulator_feedback.text = "Give the emulator a name."
		_emulator_feedback.add_theme_color_override("font_color", ERROR_COLOR)
		return
	var platform_ids: Array = []
	for platform_id in _emulator_platform_checks:
		var check: CheckBox = _emulator_platform_checks[platform_id]
		if check.button_pressed:
			platform_ids.append(platform_id)

	var data := {
		"name": name,
		"platforms": platform_ids,
	}
	var repo_url := _emulator_repo_edit.text.strip_edges()
	if repo_url != "":
		var parsed: Dictionary = UpdateManager.parse_repo_url(repo_url)
		if parsed.is_empty():
			_emulator_feedback.text = "Couldn't parse that repo URL (expected like https://github.com/owner/repo) - emulator saved without it, add it later from its row."
			_emulator_feedback.add_theme_color_override("font_color", ERROR_COLOR)
		else:
			data["source"] = {
				"type": "git_releases",
				"repo": parsed["repo"],
				"api_base": parsed["api_base"],
				"asset_pattern": "*.AppImage",
			}

	EmulatorRegistry.add_emulator(data)

	_emulator_name_edit.text = ""
	_emulator_repo_edit.text = ""
	_emulator_form.visible = false
	_refresh_emulators_tab()

## The ACTUAL root cause of "GitHub repos stopped working": this used to
## leave a GitHub api_base ("https://api.github.com") untouched instead of
## converting it back to the real web URL, so a GitHub emulator's repo
## field displayed as "https://api.github.com/<repo>". Pressing "Save Repo"
## again with no other change then fed that back through parse_repo_url,
## which saw host "api.github.com" (not "github.com"), assumed a self-
## hosted Gitea/Forgejo instance, and wrote api_base back as
## "https://api.github.com/api/v1" - a URL with no matching route on
## GitHub, confirmed on disk for eglantine/lichii/melonds in
## user://emulators.json. Every subsequent fetch against that corrupted
## api_base failed regardless of rate limits. Now explicitly maps the
## GitHub api_base back to "https://github.com" so the round-trip is
## lossless, and parse_repo_url (UpdateManager) also treats "api.github.com"
## as GitHub defensively, so pasting the API host back in can't repeat this.
func _display_repo_url(source: Dictionary) -> String:
	var repo: String = source.get("repo", "")
	if repo == "":
		return ""
	var api_base: String = source.get("api_base", UpdateManager.GITHUB_API_BASE)
	var web_base: String
	if api_base == UpdateManager.GITHUB_API_BASE:
		web_base = "https://github.com"
	elif api_base.ends_with("/api/v1"):
		web_base = api_base.substr(0, api_base.length() - "/api/v1".length())
	else:
		web_base = api_base
	return "%s/%s" % [web_base, repo]

## Excludes recomps (EmulatorRegistry.is_recomp) - those get their own
## "+ Add Recomp" form and list in the Recomps tab (_refresh_recomps_tab),
## kept separate since a recomp isn't something you'd ever assign to a ROM
## the way an emulator is.
func _refresh_emulators_tab() -> void:
	for child in _emulators_list.get_children():
		child.queue_free()

	var emulator_ids: Array = []
	for emulator_id in EmulatorRegistry.emulators:
		if not EmulatorRegistry.is_recomp(emulator_id):
			emulator_ids.append(emulator_id)

	if emulator_ids.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No emulators yet."
		empty_label.add_theme_color_override("font_color", INACTIVE_COLOR)
		_emulators_list.add_child(empty_label)
		return

	for emulator_id in emulator_ids:
		_emulators_list.add_child(_build_emulator_row(emulator_id))

func _build_emulator_row(emulator_id: String) -> VBoxContainer:
	var emulator: Dictionary = EmulatorRegistry.get_emulator(emulator_id)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)

	var platform_names: Array = []
	for platform_id in emulator.get("platforms", []):
		platform_names.append(EmulatorRegistry.get_platform(platform_id).get("name", platform_id))
	var installed_count: int = EmulatorRegistry.installed_versions(emulator_id).size()

	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 12)
	var header_label := Label.new()
	header_label.text = "%s — %s — %d version(s) installed" % [
		emulator.get("name", emulator_id),
		", ".join(platform_names) if not platform_names.is_empty() else "no platforms assigned",
		installed_count,
	]
	header_label.add_theme_font_size_override("font_size", 18)
	header_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(header_label)
	var delete_button := Button.new()
	delete_button.text = "Delete"
	delete_button.pressed.connect(_on_delete_emulator_pressed.bind(emulator_id))
	header_row.add_child(delete_button)
	box.add_child(header_row)

	var repo_row := HBoxContainer.new()
	repo_row.add_theme_constant_override("separation", 8)
	var repo_edit := LineEdit.new()
	repo_edit.placeholder_text = "Repo URL (any git host) - e.g. https://github.com/owner/repo"
	repo_edit.text = _display_repo_url(emulator.get("source", {}))
	repo_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	repo_row.add_child(repo_edit)
	var pattern_edit := LineEdit.new()
	pattern_edit.placeholder_text = "asset pattern"
	pattern_edit.text = emulator.get("source", {}).get("asset_pattern", "*.AppImage")
	pattern_edit.custom_minimum_size = Vector2(180, 0)
	repo_row.add_child(pattern_edit)
	var repo_save_button := Button.new()
	repo_save_button.text = "Save Repo"
	repo_row.add_child(repo_save_button)
	box.add_child(repo_row)

	var local_row := HBoxContainer.new()
	local_row.add_theme_constant_override("separation", 8)
	var path_edit := LineEdit.new()
	path_edit.placeholder_text = "/home/you/Emulators/eden.AppImage"
	path_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	local_row.add_child(path_edit)
	_add_browse_button(local_row, path_edit, FileDialog.FILE_MODE_OPEN_FILE, "*.AppImage", "AppImage")
	var version_edit := LineEdit.new()
	version_edit.placeholder_text = "version label"
	version_edit.custom_minimum_size = Vector2(140, 0)
	local_row.add_child(version_edit)
	var add_local_button := Button.new()
	add_local_button.text = "Add Local .AppImage"
	local_row.add_child(add_local_button)
	box.add_child(local_row)

	var feedback := Label.new()
	feedback.add_theme_color_override("font_color", FEEDBACK_COLOR)
	box.add_child(feedback)

	add_local_button.pressed.connect(func():
		var result: Dictionary = UpdateManager.install_local_file(emulator_id, version_edit.text.strip_edges(), path_edit.text.strip_edges())
		feedback.text = result.get("message", "")
		feedback.add_theme_color_override("font_color", FEEDBACK_COLOR if result.get("ok", false) else ERROR_COLOR)
		if result.get("ok", false):
			path_edit.text = ""
			version_edit.text = ""
			_refresh_emulators_tab()
	)

	repo_save_button.pressed.connect(func():
		var url := repo_edit.text.strip_edges()
		if url == "":
			var cleared: Dictionary = emulator.duplicate(true)
			cleared["source"] = {"type": "none"}
			EmulatorRegistry.update_emulator(emulator_id, cleared)
			feedback.text = "Repo cleared."
			feedback.add_theme_color_override("font_color", FEEDBACK_COLOR)
			return
		var parsed: Dictionary = UpdateManager.parse_repo_url(url)
		if parsed.is_empty():
			feedback.text = "Couldn't parse that as a repo URL (expected like https://github.com/owner/repo)."
			feedback.add_theme_color_override("font_color", ERROR_COLOR)
			return
		var pattern := pattern_edit.text.strip_edges()
		if pattern == "":
			pattern = "*.AppImage"
		var updated: Dictionary = emulator.duplicate(true)
		updated["source"] = {
			"type": "git_releases",
			"repo": parsed["repo"],
			"api_base": parsed["api_base"],
			"asset_pattern": pattern,
		}
		EmulatorRegistry.update_emulator(emulator_id, updated)
		feedback.text = "Repo set to %s. Check a compatible game's Settings → Emulator tab for its releases." % parsed["repo"]
		feedback.add_theme_color_override("font_color", FEEDBACK_COLOR)
	)

	return box

func _on_delete_emulator_pressed(emulator_id: String) -> void:
	# _build_emulator_row is shared between the Emulators and Recomps tabs
	# (see _refresh_recomps_tab) - check is_recomp before deleting, since
	# the entry (and its integration_mode) is gone right after.
	var was_recomp := EmulatorRegistry.is_recomp(emulator_id)
	EmulatorRegistry.delete_emulator(emulator_id)
	if was_recomp:
		_refresh_recomps_tab()
	else:
		_refresh_emulators_tab()

func _refresh_update_check_label() -> void:
	_update_check_label.text = "Last checked for emulator updates: %s" % UpdateManager.last_checked_text()

# ======================== Recomps ========================
# Deliberately a separate tab/form from Emulators, even though both are
# EmulatorRegistry entries under the hood (_build_emulator_row is reused
# as-is for both lists) - a recomp isn't something you'd ever assign to a
# ROM the way an emulator is, it's specific to the one game it already is,
# so mixing its "+ Add" form into the Emulators tab would be misleading.

func _build_recomps_pane() -> void:
	var hint := Label.new()
	hint.text = "Recomps are native ports with no ROM of their own - tracked for updates via their own git releases, same idea as an emulator, but kept in their own tab since a recomp is specific to the one game it already is, not something you'd assign to a ROM. They show up in the Recomps section of the side menu, and on Library's \"Native Recompilations\" tab."
	hint.add_theme_color_override("font_color", INACTIVE_COLOR)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	recomps_pane.add_child(hint)

	_build_install_dir_row(
		recomps_pane,
		"Recomps download folder",
		EmulatorRegistry.recomps_install_dir(),
		EmulatorRegistry.default_recomps_install_dir(),
		Callable(EmulatorRegistry, "set_recomps_install_dir"),
	)
	recomps_pane.add_child(HSeparator.new())

	var toggle_button := Button.new()
	toggle_button.text = "+ Add Recomp"
	recomps_pane.add_child(toggle_button)

	_recomp_form = VBoxContainer.new()
	_recomp_form.visible = false
	_recomp_form.add_theme_constant_override("separation", 8)
	recomps_pane.add_child(_recomp_form)

	toggle_button.pressed.connect(func():
		_recomp_form.visible = not _recomp_form.visible
		if _recomp_form.visible:
			_rebuild_recomp_form_checks()
	)

	_recomp_name_edit = LineEdit.new()
	_recomp_name_edit.placeholder_text = "Recomp name (e.g. The Oracles Project)"
	_recomp_form.add_child(_recomp_name_edit)

	_recomp_repo_edit = LineEdit.new()
	_recomp_repo_edit.placeholder_text = "Repo URL (optional, any git host - e.g. https://github.com/owner/repo) - can add/change this later too"
	_recomp_form.add_child(_recomp_repo_edit)

	var checks_label := Label.new()
	checks_label.text = "Belongs to these platform(s):"
	_recomp_form.add_child(checks_label)

	_recomp_checks_container = VBoxContainer.new()
	_recomp_form.add_child(_recomp_checks_container)

	var save_button := Button.new()
	save_button.text = "Save Recomp"
	save_button.pressed.connect(_on_save_recomp_pressed)
	_recomp_form.add_child(save_button)

	_recomp_feedback = Label.new()
	_recomp_feedback.add_theme_color_override("font_color", FEEDBACK_COLOR)
	_recomp_form.add_child(_recomp_feedback)

	recomps_pane.add_child(HSeparator.new())

	_recomps_list = VBoxContainer.new()
	_recomps_list.add_theme_constant_override("separation", 16)
	recomps_pane.add_child(_recomps_list)

	_refresh_recomps_tab()

var _recomp_checks_container: VBoxContainer

func _rebuild_recomp_form_checks() -> void:
	for child in _recomp_checks_container.get_children():
		child.queue_free()
	_recomp_platform_checks.clear()
	for platform_id in EmulatorRegistry.platforms:
		var platform: Dictionary = EmulatorRegistry.get_platform(platform_id)
		var check := CheckBox.new()
		check.text = platform.get("name", platform_id)
		# Default-checked for the overwhelmingly common case - still a
		# plain checkbox, so picking something else instead is one click.
		check.button_pressed = platform_id == "recomp"
		_recomp_checks_container.add_child(check)
		_recomp_platform_checks[platform_id] = check

func _on_save_recomp_pressed() -> void:
	var name := _recomp_name_edit.text.strip_edges()
	if name == "":
		_recomp_feedback.text = "Give the recomp a name."
		_recomp_feedback.add_theme_color_override("font_color", ERROR_COLOR)
		return
	var platform_ids: Array = []
	for platform_id in _recomp_platform_checks:
		var check: CheckBox = _recomp_platform_checks[platform_id]
		if check.button_pressed:
			platform_ids.append(platform_id)

	# integration_mode "recomp" + an empty args_template is what makes this
	# a recomp rather than a plain emulator (see EmulatorRegistry.is_recomp
	# and LaunchManager's no-ROM standalone launch) - a bare add_emulator()
	# call would otherwise default launch to ["{rom_path}"], wrong for a
	# self-contained binary with no ROM to pass.
	var data := {
		"name": name,
		"platforms": platform_ids,
		"integration_mode": "recomp",
		"launch": {"args_template": []},
	}
	var repo_url := _recomp_repo_edit.text.strip_edges()
	if repo_url != "":
		var parsed: Dictionary = UpdateManager.parse_repo_url(repo_url)
		if parsed.is_empty():
			_recomp_feedback.text = "Couldn't parse that repo URL (expected like https://github.com/owner/repo) - recomp saved without it, add it later from its row."
			_recomp_feedback.add_theme_color_override("font_color", ERROR_COLOR)
		else:
			data["source"] = {
				"type": "git_releases",
				"repo": parsed["repo"],
				"api_base": parsed["api_base"],
				"asset_pattern": "*.AppImage",
			}

	EmulatorRegistry.add_emulator(data)

	_recomp_name_edit.text = ""
	_recomp_repo_edit.text = ""
	_recomp_form.visible = false
	_refresh_recomps_tab()

## Reuses _build_emulator_row as-is (name/platforms/installed-count header,
## repo editor, "Add Local .AppImage", Delete) - none of that is actually
## emulator-specific, it's just "an EmulatorRegistry entry's row".
func _refresh_recomps_tab() -> void:
	for child in _recomps_list.get_children():
		child.queue_free()

	var recomp_ids: Array = EmulatorRegistry.recomp_ids()
	if recomp_ids.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No recomps yet."
		empty_label.add_theme_color_override("font_color", INACTIVE_COLOR)
		_recomps_list.add_child(empty_label)
		return

	for recomp_id in recomp_ids:
		_recomps_list.add_child(_build_emulator_row(recomp_id))

# ======================== Art ========================

func _build_art_pane() -> void:
	var hint := Label.new()
	hint.text = "Cover art comes from SteamGridDB (needs a free API key - steamgriddb.com/profile/preferences) or a file you upload yourself, per game, from its Settings page."
	hint.add_theme_color_override("font_color", INACTIVE_COLOR)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	art_pane.add_child(hint)

	var key_row := HBoxContainer.new()
	key_row.add_theme_constant_override("separation", 12)
	art_pane.add_child(key_row)

	var key_edit := LineEdit.new()
	key_edit.secret = true
	key_edit.text = ArtManager.get_api_key()
	key_edit.placeholder_text = "SteamGridDB API key"
	key_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	key_row.add_child(key_edit)

	var reveal_button := Button.new()
	reveal_button.text = "Show"
	reveal_button.toggle_mode = true
	reveal_button.toggled.connect(func(pressed: bool):
		key_edit.secret = not pressed
		reveal_button.text = "Hide" if pressed else "Show"
	)
	key_row.add_child(reveal_button)

	var save_button := Button.new()
	save_button.text = "Save Key"
	key_row.add_child(save_button)

	var feedback := Label.new()
	feedback.add_theme_color_override("font_color", FEEDBACK_COLOR)
	art_pane.add_child(feedback)

	save_button.pressed.connect(func():
		ArtManager.set_api_key(key_edit.text)
		feedback.text = "Saved." if ArtManager.has_api_key() else "Key cleared."
	)
