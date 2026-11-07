extends Control
## Per-game settings. "Emulator" tab is the real feature here: if the
## platform supports multiple emulators, every one of them gets its own
## section listing its releases (fetched live from GitHub) - installed
## versions are one click to switch to, not-yet-installed ones download
## first. Picking any version sets this game's override via
## LibraryScanner.set_override(), independent of the platform default.
##
## "General" has the rename field - a display-name override that never
## touches the actual ROM file or Quiver folder on disk
## (LibraryScanner.set_display_name) - plus static platform/id info.

const ACTIVE_COLOR := Color(0.4, 0.85, 0.5, 1)
const DOWNLOAD_COLOR := Color(0.6, 0.65, 0.7, 1)

@onready var game_title_label: Label = %GameTitleLabel
@onready var general_tab_button: Button = %GeneralTabButton
@onready var emulator_tab_button: Button = %EmulatorTabButton
@onready var art_tab_button: Button = %ArtTabButton
@onready var general_pane: VBoxContainer = %GeneralPane
@onready var emulator_pane: VBoxContainer = %EmulatorPane
@onready var art_pane: VBoxContainer = %ArtPane

var _game_id: String = ""

func set_args(args: Dictionary) -> void:
	_game_id = args.get("game_id", "")

func _ready() -> void:
	var shell := get_tree().get_first_node_in_group("shell")
	var game := LibraryScanner.get_game(_game_id)
	game_title_label.text = game.get("title", "Game")
	if shell:
		shell.set_title("%s — Settings" % game.get("title", "Game"))

	general_tab_button.pressed.connect(func(): _show_tab("general"))
	emulator_tab_button.pressed.connect(func(): _show_tab("emulator"))
	art_tab_button.pressed.connect(func(): _show_tab("art"))

	_build_general_pane(game)
	_build_emulator_pane(game)
	_build_art_pane(game)
	_show_tab("general")

	general_tab_button.grab_focus()

func _show_tab(tab: String) -> void:
	general_pane.visible = tab == "general"
	emulator_pane.visible = tab == "emulator"
	art_pane.visible = tab == "art"
	general_tab_button.add_theme_color_override("font_color", Color.WHITE if tab == "general" else DOWNLOAD_COLOR)
	emulator_tab_button.add_theme_color_override("font_color", Color.WHITE if tab == "emulator" else DOWNLOAD_COLOR)
	art_tab_button.add_theme_color_override("font_color", Color.WHITE if tab == "art" else DOWNLOAD_COLOR)
	# Switching tabs only toggled .visible above, leaving focus wherever it
	# was (usually the sidebar tab button just pressed) - a controller had
	# nothing inside ContentScroll to navigate onto, so follow_focus (see
	# GameSettings.tscn) never had anything to scroll to. Same class of bug
	# as every other grab_focus() fix in this file.
	var pane := general_pane if tab == "general" else (emulator_pane if tab == "emulator" else art_pane)
	_grab_first_focusable(pane)

## Depth-first search for the first visible, focusable control under
## `root` - used to hand the controller something to land on whenever a
## pane is shown or rebuilt (see _show_tab and _build_emulator_pane).
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

func _build_general_pane(game: Dictionary, flash_message: String = "") -> void:
	for child in general_pane.get_children():
		child.queue_free()

	var name_label := Label.new()
	name_label.text = "Display name"
	name_label.add_theme_font_size_override("font_size", 18)
	general_pane.add_child(name_label)

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 12)
	general_pane.add_child(name_row)

	var name_edit := LineEdit.new()
	name_edit.text = game.get("title", "")
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(name_edit)

	var save_name_button := Button.new()
	save_name_button.text = "Save"
	name_row.add_child(save_name_button)

	var reset_name_button := Button.new()
	reset_name_button.text = "Reset"
	name_row.add_child(reset_name_button)

	var name_hint := Label.new()
	name_hint.text = "Renaming here only changes what's shown - the ROM file / Quiver folder on disk is never touched. Original: %s" % game.get("scanned_title", game.get("title", "?"))
	name_hint.add_theme_color_override("font_color", DOWNLOAD_COLOR)
	name_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	general_pane.add_child(name_hint)

	var name_feedback := Label.new()
	name_feedback.text = flash_message
	name_feedback.add_theme_color_override("font_color", ACTIVE_COLOR)
	general_pane.add_child(name_feedback)

	var do_save := func():
		LibraryScanner.set_display_name(_game_id, name_edit.text)
		_refresh_after_rename("Saved.")
	var do_reset := func():
		LibraryScanner.set_display_name(_game_id, "")
		_refresh_after_rename("Reset to original name.")

	save_name_button.pressed.connect(do_save)
	reset_name_button.pressed.connect(do_reset)
	# Enter inside the field submits too - easy to miss the physical Save
	# button via controller/virtual keyboard, and pressing Enter to confirm
	# text entry is the natural expectation either way.
	name_edit.text_submitted.connect(func(_text: String): do_save.call())

	general_pane.add_child(HSeparator.new())

	var platform: Dictionary = EmulatorRegistry.get_platform(game.get("platform_id", ""))
	var lines := [
		"Platform: %s" % platform.get("name", "?"),
		"Game ID: %s" % game.get("id", "?"),
	]
	for line in lines:
		var label := Label.new()
		label.text = line
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		general_pane.add_child(label)

func _refresh_after_rename(message: String) -> void:
	var updated := LibraryScanner.get_game(_game_id)
	game_title_label.text = updated.get("title", "Game")
	var shell := get_tree().get_first_node_in_group("shell")
	if shell:
		shell.set_title("%s — Settings" % updated.get("title", "Game"))
	_build_general_pane(updated, message)

func _build_emulator_pane(game: Dictionary) -> void:
	for child in emulator_pane.get_children():
		child.queue_free()

	var platform_id: String = game.get("platform_id", "")
	var emulator_ids: Array = EmulatorRegistry.emulators_for_platform(platform_id)
	if emulator_ids.is_empty():
		var label := Label.new()
		label.text = "This platform has no emulator assigned (native game)."
		emulator_pane.add_child(label)
		return

	# Each emulator gets a collapsible section instead of always-expanded
	# release lists - with several emulators assigned to one platform, all
	# expanded at once was a wall of version buttons to scroll through.
	# Whichever emulator this game is actually resolved to starts expanded
	# (that's the one someone opening this tab almost always cares about);
	# the rest start collapsed.
	var current_emulator_id: String = game.get("resolved_emulator_id", "")
	for emulator_id in emulator_ids:
		var emulator: Dictionary = EmulatorRegistry.get_emulator(emulator_id)
		var expanded: bool = emulator_id == current_emulator_id or emulator_ids.size() == 1

		var section := VBoxContainer.new()
		section.add_theme_constant_override("separation", 6)
		emulator_pane.add_child(section)

		var header := Button.new()
		header.flat = true
		header.alignment = HORIZONTAL_ALIGNMENT_LEFT
		header.add_theme_font_size_override("font_size", 20)
		section.add_child(header)

		var list_box := VBoxContainer.new()
		list_box.add_theme_constant_override("separation", 4)
		list_box.visible = expanded
		section.add_child(list_box)

		var set_header_text := func(is_expanded: bool):
			header.text = ("▾  " if is_expanded else "▸  ") + emulator.get("name", emulator_id)
		set_header_text.call(expanded)
		header.pressed.connect(func():
			list_box.visible = not list_box.visible
			set_header_text.call(list_box.visible)
		)

		var loading := Label.new()
		loading.text = "Fetching releases..."
		loading.add_theme_color_override("font_color", DOWNLOAD_COLOR)
		list_box.add_child(loading)

		_populate_emulator_versions(emulator_id, list_box, loading, game)

	_grab_first_focusable(emulator_pane)

func _populate_emulator_versions(emulator_id: String, list_box: VBoxContainer, loading: Label, game: Dictionary) -> void:
	var emulator: Dictionary = EmulatorRegistry.get_emulator(emulator_id)
	var source: Dictionary = emulator.get("source", {})
	var releases: Array = []
	var repo: String = source.get("repo", "")
	if repo != "":
		var api_base: String = source.get("api_base", "https://api.github.com")
		releases = await UpdateManager.list_releases(repo, api_base)

	if not is_instance_valid(loading):
		return  # pane was rebuilt/torn down while we were awaiting the network
	loading.queue_free()

	var pattern: String = source.get("asset_pattern", "*")
	var rows := _merge_versions(emulator_id, releases, pattern)

	if rows.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No releases found (check this emulator's repo/network, or install manually)."
		empty_label.add_theme_color_override("font_color", DOWNLOAD_COLOR)
		list_box.add_child(empty_label)
		return

	var active_version: Variant = EmulatorRegistry.emulator_state.get(emulator_id, {}).get("active", null)
	var current_emulator_id: String = game.get("resolved_emulator_id", "")
	var current_version: Variant = game.get("resolved_version", null)

	for row in rows:
		var is_current: bool = current_emulator_id == emulator_id and (
			(current_version != null and current_version == row["version"])
			or (current_version == null and row["version"] == active_version)
		)
		list_box.add_child(_make_version_row(emulator_id, row, is_current, game))

func _merge_versions(emulator_id: String, releases: Array, pattern: String) -> Array:
	var seen := {}
	var rows: Array = []
	for release in releases:
		var tag: String = release.get("tag", "")
		if tag == "":
			continue
		seen[tag] = true
		rows.append({
			"version": tag,
			"installed": EmulatorRegistry.is_version_installed(emulator_id, tag),
			"asset_url": UpdateManager.find_asset_url(release, pattern),
		})
	for version in EmulatorRegistry.installed_versions(emulator_id):
		if not seen.has(version):
			rows.append({"version": version, "installed": true, "asset_url": ""})
	return rows

func _make_version_row(emulator_id: String, row: Dictionary, is_current: bool, game: Dictionary) -> Button:
	var button := Button.new()
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.focus_mode = Control.FOCUS_ALL
	_set_row_text(button, row, is_current)

	button.pressed.connect(func(): _on_version_pressed(emulator_id, row, button, game))
	return button

func _set_row_text(button: Button, row: Dictionary, is_current: bool) -> void:
	var version: String = row.get("version", "?")
	var prefix := "●  " if is_current else "    "
	var suffix := "  —  Installed" if row.get("installed", false) else "  —  Download"
	button.text = prefix + version + suffix
	button.add_theme_color_override("font_color", ACTIVE_COLOR if is_current else Color.WHITE)

func _on_version_pressed(emulator_id: String, row: Dictionary, button: Button, game: Dictionary) -> void:
	var version: String = row.get("version", "")
	if row.get("installed", false):
		LibraryScanner.set_override(_game_id, emulator_id, version)
		_build_emulator_pane(LibraryScanner.get_game(_game_id))
		return

	button.disabled = true
	button.text = "    %s  —  Downloading..." % version
	var ok: bool = await UpdateManager.install_version(emulator_id, version, row.get("asset_url", ""))
	if not is_instance_valid(button):
		return
	if ok:
		LibraryScanner.set_override(_game_id, emulator_id, version)
		_build_emulator_pane(LibraryScanner.get_game(_game_id))
	else:
		button.disabled = false
		button.text = "    %s  —  Download failed (retry)" % version

# ======================== Art ========================
# Two independent kinds, not one: "cover" (portrait, SteamGridDB Grids -
# what tiles use) and "hero" (wide backdrop, SteamGridDB Heroes - what
# GameDetail's banner uses). Stretching a portrait cover across a wide
# banner looked wrong, so they're kept as genuinely separate assets with
# their own upload/search/preview, not one image reused two ways.

func _build_art_pane(game: Dictionary) -> void:
	for child in art_pane.get_children():
		child.queue_free()
	_build_art_section(game, "cover", "Cover Art (portrait, used on tiles)", Vector2(200, 300), "*.png,*.jpg,*.jpeg,*.webp,*.bmp")
	art_pane.add_child(HSeparator.new())
	_build_art_section(game, "hero", "Hero Art (wide banner, used on this page)", Vector2(420, 136), "*.png,*.jpg,*.jpeg,*.webp,*.bmp")

func _build_art_section(game: Dictionary, kind: String, label_text: String, preview_size: Vector2, filter: String) -> void:
	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", 8)
	art_pane.add_child(section)

	var header := Label.new()
	header.text = label_text
	header.add_theme_font_size_override("font_size", 20)
	section.add_child(header)

	var preview := TextureRect.new()
	preview.custom_minimum_size = preview_size
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.clip_contents = true
	_refresh_art_preview(preview, kind, game)
	section.add_child(preview)

	var actions_row := HBoxContainer.new()
	actions_row.add_theme_constant_override("separation", 12)
	section.add_child(actions_row)

	var upload_button := Button.new()
	upload_button.text = "Upload Image..."
	actions_row.add_child(upload_button)

	var remove_button := Button.new()
	remove_button.text = "Remove"
	actions_row.add_child(remove_button)

	var feedback := Label.new()
	feedback.add_theme_color_override("font_color", DOWNLOAD_COLOR)
	section.add_child(feedback)

	upload_button.pressed.connect(func():
		var dialog := FileDialog.new()
		dialog.access = FileDialog.ACCESS_FILESYSTEM
		dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		dialog.add_filter(filter, "Images")
		dialog.size = Vector2i(900, 600)
		add_child(dialog)
		dialog.file_selected.connect(func(path: String):
			var result: Dictionary
			if kind == "hero":
				result = ArtManager.set_local_hero(_game_id, path)
			else:
				result = ArtManager.set_local_art(_game_id, path)
			feedback.text = result.get("message", "")
			feedback.add_theme_color_override("font_color", ACTIVE_COLOR if result.get("ok", false) else Color(0.9, 0.45, 0.45, 1))
			if result.get("ok", false):
				_refresh_art_preview(preview, kind, LibraryScanner.get_game(_game_id))
			dialog.queue_free()
		)
		dialog.canceled.connect(func(): dialog.queue_free())
		dialog.popup_centered()
	)

	remove_button.pressed.connect(func():
		if kind == "hero":
			ArtManager.remove_hero(_game_id)
		else:
			ArtManager.remove_art(_game_id)
		feedback.text = "Removed."
		feedback.add_theme_color_override("font_color", DOWNLOAD_COLOR)
		_refresh_art_preview(preview, kind, LibraryScanner.get_game(_game_id))
	)

	if not ArtManager.has_api_key():
		var hint := Label.new()
		hint.text = "Add a SteamGridDB API key in Settings → Art to search here."
		hint.add_theme_color_override("font_color", DOWNLOAD_COLOR)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		section.add_child(hint)
		return

	var search_button := Button.new()
	search_button.text = "Search SteamGridDB for '%s'" % game.get("title", "")
	search_button.clip_text = true
	search_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	section.add_child(search_button)

	var results_box := VBoxContainer.new()
	results_box.add_theme_constant_override("separation", 8)
	section.add_child(results_box)

	search_button.pressed.connect(func(): _search_steamgriddb(kind, game.get("title", ""), results_box, preview, feedback))

func _refresh_art_preview(preview: TextureRect, kind: String, game: Dictionary) -> void:
	var path: String
	if kind == "hero":
		path = ArtManager.get_hero_path(game.get("id", ""))
	else:
		path = ArtManager.get_art_path(game.get("id", ""))
	if path == "":
		preview.texture = null
		return
	var image := Image.new()
	if image.load(path) == OK:
		preview.texture = ImageTexture.create_from_image(image)

func _search_steamgriddb(kind: String, title: String, results_box: VBoxContainer, preview: TextureRect, feedback: Label) -> void:
	for child in results_box.get_children():
		child.queue_free()
	var loading := Label.new()
	loading.text = "Searching..."
	loading.add_theme_color_override("font_color", DOWNLOAD_COLOR)
	results_box.add_child(loading)

	var matches: Array = await ArtManager.search(title)
	if not is_instance_valid(results_box):
		return
	loading.queue_free()

	if matches.is_empty():
		var empty := Label.new()
		empty.text = "No matches found."
		empty.add_theme_color_override("font_color", DOWNLOAD_COLOR)
		results_box.add_child(empty)
		return

	var first_candidate_button: Button = null
	for candidate in matches.slice(0, 5):
		var candidate_button := Button.new()
		candidate_button.text = candidate.get("name", "?")
		candidate_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		results_box.add_child(candidate_button)
		candidate_button.pressed.connect(func(): _show_image_candidates(kind, candidate.get("id", 0), results_box, preview, feedback))
		if first_candidate_button == null:
			first_candidate_button = candidate_button

	# Same reasoning as the thumbnail step below: whatever had focus before
	# this search (e.g. a candidate button from a previous search) may have
	# just been freed, so explicitly claim focus rather than leave a
	# controller with nothing to navigate from.
	if first_candidate_button != null:
		first_candidate_button.grab_focus()

func _show_image_candidates(kind: String, steamgriddb_id: int, results_box: VBoxContainer, preview: TextureRect, feedback: Label) -> void:
	for child in results_box.get_children():
		child.queue_free()
	var loading := Label.new()
	loading.text = "Loading options..."
	loading.add_theme_color_override("font_color", DOWNLOAD_COLOR)
	results_box.add_child(loading)

	var images: Array
	if kind == "hero":
		images = await ArtManager.get_heroes(steamgriddb_id)
	else:
		images = await ArtManager.get_grids(steamgriddb_id)
	if not is_instance_valid(results_box):
		return
	loading.queue_free()

	if images.is_empty():
		var empty := Label.new()
		empty.text = "No art found for that match."
		empty.add_theme_color_override("font_color", DOWNLOAD_COLOR)
		results_box.add_child(empty)
		return

	var thumbs_row := HBoxContainer.new()
	thumbs_row.add_theme_constant_override("separation", 10)
	results_box.add_child(thumbs_row)

	for image_entry in images.slice(0, 6):
		_add_thumb_button(kind, image_entry, thumbs_row, preview, feedback)

	# The candidate button that was just clicked (and focused) to get here
	# is about to be freed along with the rest of results_box's old
	# children - without this, focus is simply lost and a controller has
	# nothing to navigate from, same class of bug as every grab_focus() fix
	# elsewhere. Thumb buttons are already in the tree synchronously here
	# (their own icon-loading await happens after they're added).
	if thumbs_row.get_child_count() > 0:
		thumbs_row.get_child(0).grab_focus()

func _add_thumb_button(kind: String, image_entry: Dictionary, thumbs_row: HBoxContainer, preview: TextureRect, feedback: Label) -> void:
	var thumb_button := Button.new()
	thumb_button.custom_minimum_size = Vector2(120, 72) if kind == "hero" else Vector2(90, 135)
	thumb_button.text = "…"
	thumbs_row.add_child(thumb_button)

	var bytes: PackedByteArray = await ArtManager.download_bytes(image_entry.get("thumb", ""))
	if not is_instance_valid(thumb_button):
		return
	if not bytes.is_empty():
		var image := Image.new()
		var ext: String = String(image_entry.get("thumb", "")).get_extension().to_lower()
		var err := ERR_UNAVAILABLE
		if ext == "png":
			err = image.load_png_from_buffer(bytes)
		elif ext in ["jpg", "jpeg"]:
			err = image.load_jpg_from_buffer(bytes)
		elif ext == "webp":
			err = image.load_webp_from_buffer(bytes)
		if err == OK:
			thumb_button.text = ""
			thumb_button.icon = ImageTexture.create_from_image(image)
			thumb_button.expand_icon = true

	thumb_button.pressed.connect(func():
		feedback.text = "Downloading..."
		feedback.add_theme_color_override("font_color", DOWNLOAD_COLOR)
		var result: Dictionary
		if kind == "hero":
			result = await ArtManager.install_hero(_game_id, image_entry.get("url", ""))
		else:
			result = await ArtManager.install_grid(_game_id, image_entry.get("url", ""))
		feedback.text = result.get("message", "")
		feedback.add_theme_color_override("font_color", ACTIVE_COLOR if result.get("ok", false) else Color(0.9, 0.45, 0.45, 1))
		if result.get("ok", false):
			_refresh_art_preview(preview, kind, LibraryScanner.get_game(_game_id))
	)
