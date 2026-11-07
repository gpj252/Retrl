extends Control
## A single emulator's own page: which platforms it runs, a Launch button
## (starts its active version standalone, same as GameDetail's "Open
## Emulator" but with no game involved at all), and two tabs - "Versions"
## (every release fetched from its repo, via UpdateManager, now cached -
## see UpdateManager.CACHE_TTL_SECONDS - with install/activate actions and a
## changelog per version, the main reason this page exists: answering
## "which version should I use for this game" without going through a
## specific game's Settings page first) and "Art" (SteamGridDB search/
## upload, same as GameSettings' Art tab but just the one "cover" kind - an
## emulator has no hero banner). Separate tabs rather than one long page -
## art management has nothing to do with picking a version and shouldn't
## compete with it for space, same sidebar-tabs pattern GameSettings and
## AppSettings already use.

const ACTIVE_COLOR := Color(0.4, 0.85, 0.5, 1)
const INACTIVE_COLOR := Color(0.6, 0.65, 0.7, 1)
const DOWNLOAD_COLOR := Color(0.6, 0.65, 0.7, 1)
const ERROR_COLOR := Color(0.9, 0.45, 0.45, 1)

@onready var title_label: Label = %TitleLabel
@onready var platforms_label: Label = %PlatformsLabel
@onready var launch_button: Button = %LaunchButton
@onready var status_label: Label = %StatusLabel
@onready var versions_tab_button: Button = %VersionsTabButton
@onready var art_tab_button: Button = %ArtTabButton
@onready var versions_pane: VBoxContainer = %VersionsPane
@onready var art_pane: VBoxContainer = %ArtPane

var _emulator_id: String = ""

func set_args(args: Dictionary) -> void:
	_emulator_id = args.get("emulator_id", "")

func _ready() -> void:
	var shell := get_tree().get_first_node_in_group("shell")
	var emulator := EmulatorRegistry.get_emulator(_emulator_id)
	if emulator.is_empty():
		title_label.text = "Emulator not found"
		if shell:
			shell.set_title("Emulator")
		return

	if shell:
		shell.set_title(emulator.get("name", _emulator_id))
	title_label.text = emulator.get("name", _emulator_id)

	versions_tab_button.pressed.connect(func(): _show_tab("versions"))
	art_tab_button.pressed.connect(func(): _show_tab("art"))

	_refresh_header()
	_build_art_pane()
	_build_versions_pane()
	_show_tab("versions")

	launch_button.pressed.connect(_on_launch_pressed)
	launch_button.grab_focus()

func _show_tab(tab: String) -> void:
	versions_pane.visible = tab == "versions"
	art_pane.visible = tab == "art"
	versions_tab_button.add_theme_color_override("font_color", Color.WHITE if tab == "versions" else INACTIVE_COLOR)
	art_tab_button.add_theme_color_override("font_color", Color.WHITE if tab == "art" else INACTIVE_COLOR)
	# Toggling .visible alone left focus wherever it was (usually the tab
	# button just pressed), with nothing inside ContentScroll for a
	# controller to land on - follow_focus (see EmulatorDetail.tscn) then
	# had nothing to scroll to. Same bug/fix as GameSettings._show_tab.
	_grab_first_focusable(versions_pane if tab == "versions" else art_pane)

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

func _refresh_header() -> void:
	var emulator := EmulatorRegistry.get_emulator(_emulator_id)
	var platform_names: Array = []
	for platform_id in emulator.get("platforms", []):
		platform_names.append(EmulatorRegistry.get_platform(platform_id).get("name", platform_id))
	var active: Variant = EmulatorRegistry.emulator_state.get(_emulator_id, {}).get("active", null)
	var installed_count: int = EmulatorRegistry.installed_versions(_emulator_id).size()

	platforms_label.text = "Platforms: %s     Installed versions: %d     Active: %s" % [
		", ".join(platform_names) if not platform_names.is_empty() else "none assigned",
		installed_count,
		active if active != null else "none",
	]
	launch_button.disabled = active == null
	launch_button.tooltip_text = "" if active != null else "Install a version below first."

func _on_launch_pressed() -> void:
	var result: Dictionary = LaunchManager.launch_emulator_standalone(_emulator_id)
	status_label.text = result.get("message", "")
	status_label.add_theme_color_override("font_color", ACTIVE_COLOR if result.get("ok", false) else ERROR_COLOR)

# ======================== Art (cover only - no hero for emulators) ========

func _art_key() -> String:
	return "emulator:%s" % _emulator_id

func _build_art_pane() -> void:
	for child in art_pane.get_children():
		child.queue_free()
	var art_key := _art_key()

	var preview := TextureRect.new()
	preview.custom_minimum_size = Vector2(160, 160)
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.clip_contents = true
	_refresh_art_preview(preview, art_key)
	art_pane.add_child(preview)

	var actions_row := HBoxContainer.new()
	actions_row.add_theme_constant_override("separation", 12)
	art_pane.add_child(actions_row)

	var upload_button := Button.new()
	upload_button.text = "Upload Image..."
	actions_row.add_child(upload_button)

	var remove_button := Button.new()
	remove_button.text = "Remove"
	actions_row.add_child(remove_button)

	var feedback := Label.new()
	feedback.add_theme_color_override("font_color", DOWNLOAD_COLOR)
	art_pane.add_child(feedback)

	upload_button.pressed.connect(func():
		var dialog := FileDialog.new()
		dialog.access = FileDialog.ACCESS_FILESYSTEM
		dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		dialog.add_filter("*.png,*.jpg,*.jpeg,*.webp,*.bmp", "Images")
		dialog.size = Vector2i(900, 600)
		add_child(dialog)
		dialog.file_selected.connect(func(path: String):
			var result: Dictionary = ArtManager.set_local_art(art_key, path)
			feedback.text = result.get("message", "")
			feedback.add_theme_color_override("font_color", ACTIVE_COLOR if result.get("ok", false) else ERROR_COLOR)
			if result.get("ok", false):
				_refresh_art_preview(preview, art_key)
			dialog.queue_free()
		)
		dialog.canceled.connect(func(): dialog.queue_free())
		dialog.popup_centered()
	)

	remove_button.pressed.connect(func():
		ArtManager.remove_art(art_key)
		feedback.text = "Removed."
		feedback.add_theme_color_override("font_color", DOWNLOAD_COLOR)
		_refresh_art_preview(preview, art_key)
	)

	if not ArtManager.has_api_key():
		var hint := Label.new()
		hint.text = "Add a SteamGridDB API key in Settings → Art to search here."
		hint.add_theme_color_override("font_color", DOWNLOAD_COLOR)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		art_pane.add_child(hint)
		return

	var emulator_name: String = EmulatorRegistry.get_emulator(_emulator_id).get("name", _emulator_id)
	var search_button := Button.new()
	search_button.text = "Search SteamGridDB for '%s'" % emulator_name
	search_button.clip_text = true
	search_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	art_pane.add_child(search_button)

	var results_box := VBoxContainer.new()
	results_box.add_theme_constant_override("separation", 8)
	art_pane.add_child(results_box)

	search_button.pressed.connect(func(): _search_steamgriddb(emulator_name, art_key, results_box, preview, feedback))

func _refresh_art_preview(preview: TextureRect, art_key: String) -> void:
	var path := ArtManager.get_art_path(art_key)
	if path == "":
		preview.texture = null
		return
	var image := Image.new()
	if image.load(path) == OK:
		preview.texture = ImageTexture.create_from_image(image)

func _search_steamgriddb(title: String, art_key: String, results_box: VBoxContainer, preview: TextureRect, feedback: Label) -> void:
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
		candidate_button.pressed.connect(func(): _show_image_candidates(candidate.get("id", 0), art_key, results_box, preview, feedback))
		if first_candidate_button == null:
			first_candidate_button = candidate_button

	if first_candidate_button != null:
		first_candidate_button.grab_focus()

func _show_image_candidates(steamgriddb_id: int, art_key: String, results_box: VBoxContainer, preview: TextureRect, feedback: Label) -> void:
	for child in results_box.get_children():
		child.queue_free()
	var loading := Label.new()
	loading.text = "Loading options..."
	loading.add_theme_color_override("font_color", DOWNLOAD_COLOR)
	results_box.add_child(loading)

	var images: Array = await ArtManager.get_grids(steamgriddb_id)
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
		_add_thumb_button(image_entry, art_key, thumbs_row, preview, feedback)

	if thumbs_row.get_child_count() > 0:
		thumbs_row.get_child(0).grab_focus()

func _add_thumb_button(image_entry: Dictionary, art_key: String, thumbs_row: HBoxContainer, preview: TextureRect, feedback: Label) -> void:
	var thumb_button := Button.new()
	thumb_button.custom_minimum_size = Vector2(90, 135)
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
		var result: Dictionary = await ArtManager.install_grid(art_key, image_entry.get("url", ""))
		feedback.text = result.get("message", "")
		feedback.add_theme_color_override("font_color", ACTIVE_COLOR if result.get("ok", false) else ERROR_COLOR)
		if result.get("ok", false):
			_refresh_art_preview(preview, art_key)
	)

# ======================== Versions ========================

func _build_versions_pane() -> void:
	for child in versions_pane.get_children():
		child.queue_free()

	var emulator := EmulatorRegistry.get_emulator(_emulator_id)
	var source: Dictionary = emulator.get("source", {})
	var repo: String = source.get("repo", "")

	var loading := Label.new()
	loading.text = "Fetching releases..." if repo != "" else "No repo configured for this emulator - showing installed versions only. Add one in Settings → Emulators."
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
		empty.text = "No releases found yet (check the repo/network in Settings, or add a local .AppImage there)."
		empty.add_theme_color_override("font_color", DOWNLOAD_COLOR)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		versions_pane.add_child(empty)
		return

	var active_version: Variant = EmulatorRegistry.emulator_state.get(_emulator_id, {}).get("active", null)
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
			"installed": EmulatorRegistry.is_version_installed(_emulator_id, tag),
			"asset_url": UpdateManager.find_asset_url(release, pattern),
		})
	for version in EmulatorRegistry.installed_versions(_emulator_id):
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
			EmulatorRegistry.set_active_version(_emulator_id, row["version"])
			_refresh_header()
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
			EmulatorRegistry.delete_installed_version(_emulator_id, row.get("version", ""))
			_refresh_header()
			_build_versions_pane()
		)
		hrow.add_child(delete_button)

	return hrow

func _on_download_pressed(row: Dictionary, button: Button) -> void:
	button.disabled = true
	button.text = "Downloading..."
	var ok: bool = await UpdateManager.install_version(_emulator_id, row.get("version", ""), row.get("asset_url", ""))
	if not is_instance_valid(button):
		return
	if ok:
		_refresh_header()
		_build_versions_pane()
	else:
		button.disabled = false
		button.text = "Download failed (retry)"

func _show_changelog(row: Dictionary) -> void:
	var emulator_name: String = EmulatorRegistry.get_emulator(_emulator_id).get("name", _emulator_id)
	var dialog := AcceptDialog.new()
	dialog.title = "%s %s" % [emulator_name, row.get("version", "")]
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
