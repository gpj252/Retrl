extends Control
## Per-recomp settings - mirrors GameSettings' sidebar-tabs layout, but with
## "Versions" in place of GameSettings' "Emulator" tab, and no "Emulator"
## tab at all: GameSettings' Emulator tab lets you pick *which* emulator
## plays a ROM, and a recomp has no ROM and no choice to make there - it
## only ever plays itself. "Versions" is the recomp-shaped equivalent of
## that same idea (which build of itself is installed/active), adapted
## from EmulatorDetail's versions pane down to a single source instead of
## one section per platform-compatible emulator (a recomp only ever has
## the one).
##
## "General" is just a rename field (EmulatorRegistry.update_emulator,
## same merge-not-clobber pattern AppSettings' repo editor uses) - a
## recomp has no ROM file/Quiver folder on disk to leave untouched, unlike
## GameSettings' rename, but the UI idea (display name only, doesn't
## affect anything else) is the same.
##
## "Art" has both cover and hero (like GameSettings - a recomp IS the game,
## so it gets the full two-kind art treatment), keyed under "recomp:<id>",
## independent of any "emulator:<id>" art the entry might carry from
## before recomps had their own section.

const ACTIVE_COLOR := Color(0.4, 0.85, 0.5, 1)
const DOWNLOAD_COLOR := Color(0.6, 0.65, 0.7, 1)
const ERROR_COLOR := Color(0.9, 0.45, 0.45, 1)

@onready var title_label: Label = %TitleLabel
@onready var general_tab_button: Button = %GeneralTabButton
@onready var versions_tab_button: Button = %VersionsTabButton
@onready var art_tab_button: Button = %ArtTabButton
@onready var general_pane: VBoxContainer = %GeneralPane
@onready var versions_pane: VBoxContainer = %VersionsPane
@onready var art_pane: VBoxContainer = %ArtPane

var _recomp_id: String = ""

func set_args(args: Dictionary) -> void:
	_recomp_id = args.get("recomp_id", "")

func _ready() -> void:
	var shell := get_tree().get_first_node_in_group("shell")
	var recomp := EmulatorRegistry.get_emulator(_recomp_id)
	title_label.text = recomp.get("name", "Recomp")
	if shell:
		shell.set_title("%s — Settings" % recomp.get("name", "Recomp"))

	general_tab_button.pressed.connect(func(): _show_tab("general"))
	versions_tab_button.pressed.connect(func(): _show_tab("versions"))
	art_tab_button.pressed.connect(func(): _show_tab("art"))

	_build_general_pane()
	_build_versions_pane()
	_build_art_pane()
	_show_tab("general")

	general_tab_button.grab_focus()

func _art_key() -> String:
	return "recomp:%s" % _recomp_id

func _show_tab(tab: String) -> void:
	general_pane.visible = tab == "general"
	versions_pane.visible = tab == "versions"
	art_pane.visible = tab == "art"
	general_tab_button.add_theme_color_override("font_color", Color.WHITE if tab == "general" else DOWNLOAD_COLOR)
	versions_tab_button.add_theme_color_override("font_color", Color.WHITE if tab == "versions" else DOWNLOAD_COLOR)
	art_tab_button.add_theme_color_override("font_color", Color.WHITE if tab == "art" else DOWNLOAD_COLOR)
	# Same follow_focus bug/fix as every other sidebar-tabs screen here
	# (GameSettings/EmulatorDetail/AppSettings) - toggling .visible alone
	# leaves focus on the tab button just pressed, with nothing inside
	# ContentScroll for a controller to land on.
	var pane := general_pane if tab == "general" else (versions_pane if tab == "versions" else art_pane)
	_grab_first_focusable(pane)

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

# ======================== General ========================

func _build_general_pane(flash_message: String = "") -> void:
	for child in general_pane.get_children():
		child.queue_free()
	var recomp := EmulatorRegistry.get_emulator(_recomp_id)

	var name_label := Label.new()
	name_label.text = "Display name"
	name_label.add_theme_font_size_override("font_size", 18)
	general_pane.add_child(name_label)

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 12)
	general_pane.add_child(name_row)

	var name_edit := LineEdit.new()
	name_edit.text = recomp.get("name", "")
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(name_edit)

	var save_name_button := Button.new()
	save_name_button.text = "Save"
	name_row.add_child(save_name_button)

	var name_feedback := Label.new()
	name_feedback.text = flash_message
	name_feedback.add_theme_color_override("font_color", ACTIVE_COLOR)
	general_pane.add_child(name_feedback)

	var do_save := func():
		var trimmed := name_edit.text.strip_edges()
		if trimmed == "":
			return
		var updated: Dictionary = recomp.duplicate(true)
		updated["name"] = trimmed
		EmulatorRegistry.update_emulator(_recomp_id, updated)
		var shell := get_tree().get_first_node_in_group("shell")
		if shell:
			shell.set_title("%s — Settings" % trimmed)
		title_label.text = trimmed
		_build_general_pane("Saved.")

	save_name_button.pressed.connect(do_save)
	name_edit.text_submitted.connect(func(_text: String): do_save.call())

	general_pane.add_child(HSeparator.new())

	var platform_ids: Array = recomp.get("platforms", [])
	var platform_names: Array = []
	for platform_id in platform_ids:
		platform_names.append(EmulatorRegistry.get_platform(platform_id).get("name", platform_id))
	var lines := [
		"Platform: %s" % (", ".join(platform_names) if not platform_names.is_empty() else "none assigned"),
		"Recomp ID: %s" % _recomp_id,
	]
	for line in lines:
		var label := Label.new()
		label.text = line
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		general_pane.add_child(label)

# ======================== Versions ========================
# Adapted from EmulatorDetail's versions pane - same UpdateManager-backed
# fetch/install/changelog flow, just scoped to this one recomp directly
# instead of one collapsible section per platform-compatible emulator.

func _build_versions_pane() -> void:
	for child in versions_pane.get_children():
		child.queue_free()

	var recomp := EmulatorRegistry.get_emulator(_recomp_id)
	var source: Dictionary = recomp.get("source", {})
	var repo: String = source.get("repo", "")

	var loading := Label.new()
	loading.text = "Fetching releases..." if repo != "" else "No repo configured for this recomp."
	loading.add_theme_color_override("font_color", DOWNLOAD_COLOR)
	loading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	versions_pane.add_child(loading)

	_populate_versions(loading, source, repo)

func _populate_versions(loading: Label, source: Dictionary, repo: String) -> void:
	var releases: Array = []
	if repo != "":
		var api_base: String = source.get("api_base", "https://api.github.com")
		releases = await UpdateManager.list_releases(repo, api_base)

	if not is_instance_valid(loading):
		return  # page was navigated away from while awaiting the network
	loading.queue_free()

	var pattern: String = source.get("asset_pattern", "*")
	var rows := _merge_versions(releases, pattern)

	if rows.is_empty():
		var empty := Label.new()
		empty.text = "No releases found yet (check the repo/network, or add one in Settings → Emulators)."
		empty.add_theme_color_override("font_color", DOWNLOAD_COLOR)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		versions_pane.add_child(empty)
		return

	var active_version: Variant = EmulatorRegistry.emulator_state.get(_recomp_id, {}).get("active", null)
	for row in rows:
		versions_pane.add_child(_make_version_row(row, row["version"] == active_version))

func _merge_versions(releases: Array, pattern: String) -> Array:
	var seen := {}
	var rows: Array = []
	for release in releases:
		var tag: String = release.get("tag", "")
		if tag == "":
			continue
		seen[tag] = true
		rows.append({
			"version": tag,
			"body": release.get("body", ""),
			"installed": EmulatorRegistry.is_version_installed(_recomp_id, tag),
			"asset_url": UpdateManager.find_asset_url(release, pattern),
		})
	for version in EmulatorRegistry.installed_versions(_recomp_id):
		if not seen.has(version):
			rows.append({"version": version, "body": "", "installed": true, "asset_url": ""})
	return rows

func _make_version_row(row: Dictionary, is_active: bool) -> HBoxContainer:
	var hrow := HBoxContainer.new()
	hrow.add_theme_constant_override("separation", 12)

	var label := Label.new()
	var prefix := "●  " if is_active else "    "
	var suffix := "  —  Installed" if row.get("installed", false) else "  —  Not installed"
	label.text = prefix + row.get("version", "?") + suffix
	label.add_theme_color_override("font_color", ACTIVE_COLOR if is_active else Color.WHITE)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hrow.add_child(label)

	var changelog_button := Button.new()
	changelog_button.text = "Changelog"
	changelog_button.disabled = String(row.get("body", "")).strip_edges() == ""
	changelog_button.pressed.connect(_show_changelog.bind(row))
	hrow.add_child(changelog_button)

	var action_button := Button.new()
	if is_active:
		action_button.text = "Active"
		action_button.disabled = true
	elif row.get("installed", false):
		action_button.text = "Set Active"
		action_button.pressed.connect(func():
			EmulatorRegistry.set_active_version(_recomp_id, row["version"])
			_build_versions_pane()
		)
	else:
		var asset_url: String = row.get("asset_url", "")
		if asset_url == "":
			action_button.text = "No matching asset"
			action_button.disabled = true
		else:
			action_button.text = "Download"
			action_button.pressed.connect(func(): _on_download_pressed(row, action_button))
	hrow.add_child(action_button)

	if row.get("installed", false):
		var delete_button := Button.new()
		delete_button.text = "Delete"
		delete_button.pressed.connect(func():
			EmulatorRegistry.delete_installed_version(_recomp_id, row.get("version", ""))
			_build_versions_pane()
		)
		hrow.add_child(delete_button)

	return hrow

func _on_download_pressed(row: Dictionary, button: Button) -> void:
	button.disabled = true
	button.text = "Downloading..."
	var ok: bool = await UpdateManager.install_version(_recomp_id, row.get("version", ""), row.get("asset_url", ""))
	if not is_instance_valid(button):
		return
	if ok:
		_build_versions_pane()
	else:
		button.disabled = false
		button.text = "Download failed (retry)"

func _show_changelog(row: Dictionary) -> void:
	var recomp_name: String = EmulatorRegistry.get_emulator(_recomp_id).get("name", _recomp_id)
	var dialog := AcceptDialog.new()
	dialog.title = "%s %s" % [recomp_name, row.get("version", "")]
	dialog.size = Vector2i(640, 480)
	dialog.get_ok_button().text = "Close"
	add_child(dialog)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(600, 400)
	dialog.add_child(scroll)

	var body_label := Label.new()
	var body_text: String = String(row.get("body", "")).strip_edges()
	body_label.text = body_text if body_text != "" else "No release notes provided."
	body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body_label.custom_minimum_size = Vector2(580, 0)
	scroll.add_child(body_label)

	dialog.confirmed.connect(func(): dialog.queue_free())
	dialog.close_requested.connect(func(): dialog.queue_free())
	dialog.popup_centered()

# ======================== Art (cover + hero, like GameSettings) ========

func _build_art_pane() -> void:
	for child in art_pane.get_children():
		child.queue_free()
	_build_art_section("cover", "Cover Art (portrait, used on tiles)", Vector2(200, 300), "*.png,*.jpg,*.jpeg,*.webp,*.bmp")
	art_pane.add_child(HSeparator.new())
	_build_art_section("hero", "Hero Art (wide banner, used on this recomp's page)", Vector2(420, 136), "*.png,*.jpg,*.jpeg,*.webp,*.bmp")

func _build_art_section(kind: String, label_text: String, preview_size: Vector2, filter: String) -> void:
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
	_refresh_art_preview(preview, kind)
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
				result = ArtManager.set_local_hero(_art_key(), path)
			else:
				result = ArtManager.set_local_art(_art_key(), path)
			feedback.text = result.get("message", "")
			feedback.add_theme_color_override("font_color", ACTIVE_COLOR if result.get("ok", false) else ERROR_COLOR)
			if result.get("ok", false):
				_refresh_art_preview(preview, kind)
			dialog.queue_free()
		)
		dialog.canceled.connect(func(): dialog.queue_free())
		dialog.popup_centered()
	)

	remove_button.pressed.connect(func():
		if kind == "hero":
			ArtManager.remove_hero(_art_key())
		else:
			ArtManager.remove_art(_art_key())
		feedback.text = "Removed."
		feedback.add_theme_color_override("font_color", DOWNLOAD_COLOR)
		_refresh_art_preview(preview, kind)
	)

	if not ArtManager.has_api_key():
		var hint := Label.new()
		hint.text = "Add a SteamGridDB API key in Settings → Art to search here."
		hint.add_theme_color_override("font_color", DOWNLOAD_COLOR)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		section.add_child(hint)
		return

	var recomp_name: String = EmulatorRegistry.get_emulator(_recomp_id).get("name", _recomp_id)
	var search_button := Button.new()
	search_button.text = "Search SteamGridDB for '%s'" % recomp_name
	search_button.clip_text = true
	search_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	section.add_child(search_button)

	var results_box := VBoxContainer.new()
	results_box.add_theme_constant_override("separation", 8)
	section.add_child(results_box)

	search_button.pressed.connect(func(): _search_steamgriddb(kind, recomp_name, results_box, preview, feedback))

func _refresh_art_preview(preview: TextureRect, kind: String) -> void:
	var path: String = ArtManager.get_hero_path(_art_key()) if kind == "hero" else ArtManager.get_art_path(_art_key())
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

	if first_candidate_button != null:
		first_candidate_button.grab_focus()

func _show_image_candidates(kind: String, steamgriddb_id: int, results_box: VBoxContainer, preview: TextureRect, feedback: Label) -> void:
	for child in results_box.get_children():
		child.queue_free()
	var loading := Label.new()
	loading.text = "Loading options..."
	loading.add_theme_color_override("font_color", DOWNLOAD_COLOR)
	results_box.add_child(loading)

	var images: Array = await ArtManager.get_heroes(steamgriddb_id) if kind == "hero" else await ArtManager.get_grids(steamgriddb_id)
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
			result = await ArtManager.install_hero(_art_key(), image_entry.get("url", ""))
		else:
			result = await ArtManager.install_grid(_art_key(), image_entry.get("url", ""))
		feedback.text = result.get("message", "")
		feedback.add_theme_color_override("font_color", ACTIVE_COLOR if result.get("ok", false) else ERROR_COLOR)
		if result.get("ok", false):
			_refresh_art_preview(preview, kind)
	)
