extends Control
## SteamOS-style home: a "Recent Games" carousel across ALL platforms,
## ordered by last played (LibraryScanner.record_played is what makes this
## real - called whenever a game is actually launched; nothing else ever
## sets last_played for ROM-scanned games). No platform/emulator picker -
## every tile already knows its own game, and the game knows its own
## emulator. Picking a game opens its GameDetail page.
##
## Below that, an "Emulator Updates" row: the latest release per emulator
## that has a real repo configured. Checked via
## UpdateManager.startup_check_for_updates, which only actually runs once
## per app session (repeat visits to Home - which happens a lot, since
## Navigator recreates this scene on every nav back here - just reuse that
## first result) and per-repo network fetches beyond that are capped to
## once a day on top of that (see UpdateManager.CACHE_TTL_SECONDS); this is
## what was blowing through GitHub's unauthenticated rate limit before.
## Settings → Emulators has a "Check for Updates Now" button for an
## on-demand recheck. Clicking a card shows that release's changelog, with
## an install/activate action right there - hidden entirely if no emulator
## has a configured repo or every check failed.

const GameTileFactory = preload("res://ui/components/game_tile_factory.gd")
const TILE_WIDTH := 200.0

@onready var tiles: HBoxContainer = %Tiles
@onready var row_scroll: ScrollContainer = %RowScroll
@onready var focused_info: Label = %FocusedInfo
@onready var updates_section: VBoxContainer = %UpdatesSection
@onready var updates_row_scroll: ScrollContainer = %UpdatesRowScroll
@onready var updates_cards: HBoxContainer = %UpdatesCards

func _ready() -> void:
	var shell := get_tree().get_first_node_in_group("shell")
	if shell:
		shell.set_title("Home")
	_build_row()
	_build_updates_row()

func _build_row() -> void:
	for child in tiles.get_children():
		child.queue_free()

	var first_tile: Button = null
	for game in LibraryScanner.games_by_recency():
		var platform: Dictionary = EmulatorRegistry.get_platform(game.get("platform_id", ""))
		var accent := Color.html(platform.get("accent_color", "#444444"))
		var tile := GameTileFactory.create(game, accent, TILE_WIDTH)
		GameTileFactory.attach_focus_feedback(tile, [row_scroll])
		tile.focus_entered.connect(_on_tile_focused.bind(game))
		tile.pressed.connect(_on_tile_pressed.bind(game))
		tiles.add_child(tile)
		if first_tile == null:
			first_tile = tile

	if first_tile != null:
		first_tile.grab_focus()

func _on_tile_focused(game: Dictionary) -> void:
	var last_played: Variant = game.get("last_played", null)
	var playtime: float = game.get("playtime_hours", 0.0)
	var when_text := "No playtime yet" if last_played == null else "Last played %s — %.1f hrs" % [last_played, playtime]
	focused_info.text = "%s — %s" % [game.get("title", "Untitled"), when_text]

func _on_tile_pressed(game: Dictionary) -> void:
	Navigator.push("res://ui/screens/GameDetail.tscn", {"game_id": game.get("id", "")})

func _build_updates_row() -> void:
	var entries: Array = await UpdateManager.startup_check_for_updates()
	if not is_instance_valid(updates_cards):
		return  # screen was navigated away from while we were awaiting the network

	for child in updates_cards.get_children():
		child.queue_free()
	updates_section.visible = not entries.is_empty()
	for entry in entries:
		updates_cards.add_child(_build_update_card(entry))

func _build_update_card(entry: Dictionary) -> Button:
	var card := Button.new()
	card.custom_minimum_size = Vector2(280, 100)
	card.focus_mode = Control.FOCUS_ALL
	card.text = ""

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 14)
	card.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 6)
	margin.add_child(vbox)

	var name_label := Label.new()
	name_label.text = String(entry.get("emulator_name", "?"))
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.add_theme_font_size_override("font_size", 18)
	vbox.add_child(name_label)

	var status_label := Label.new()
	status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var tag: String = entry.get("tag", "?")
	if entry.get("is_active", false):
		status_label.text = "Up to date — %s" % tag
		status_label.add_theme_color_override("font_color", Color(0.4, 0.85, 0.5, 1))
	elif entry.get("is_installed", false):
		status_label.text = "Downloaded — %s (not active)" % tag
		status_label.add_theme_color_override("font_color", Color(0.6, 0.65, 0.7, 1))
	else:
		status_label.text = "Update available — %s" % tag
		status_label.add_theme_color_override("font_color", Color(0.5, 0.75, 0.95, 1))
	vbox.add_child(status_label)

	card.focus_entered.connect(func(): updates_row_scroll.ensure_control_visible(card))
	card.pressed.connect(func(): _show_changelog_dialog(entry))
	return card

func _show_changelog_dialog(entry: Dictionary) -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "%s %s" % [entry.get("emulator_name", "?"), entry.get("tag", "?")]
	dialog.size = Vector2i(640, 480)
	dialog.get_ok_button().text = "Close"
	add_child(dialog)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	content.custom_minimum_size = Vector2(600, 400)
	dialog.add_child(content)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(scroll)

	var body_label := Label.new()
	var body_text: String = String(entry.get("body", "")).strip_edges()
	body_label.text = body_text if body_text != "" else "No release notes provided."
	body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body_label.custom_minimum_size = Vector2(580, 0)
	scroll.add_child(body_label)

	if not entry.get("is_active", false):
		var install_feedback := Label.new()
		install_feedback.add_theme_color_override("font_color", Color(0.6, 0.65, 0.7, 1))

		var install_button := Button.new()
		var already_installed: bool = entry.get("is_installed", false)
		install_button.text = "Set as active version" if already_installed else "Install this version"
		content.add_child(install_button)
		content.add_child(install_feedback)

		install_button.pressed.connect(func():
			var emulator_id: String = entry.get("emulator_id", "")
			var tag: String = entry.get("tag", "")
			if already_installed:
				EmulatorRegistry.set_active_version(emulator_id, tag)
				install_feedback.text = "Now active."
				install_button.disabled = true
				return
			install_button.disabled = true
			install_feedback.text = "Downloading..."
			var asset_url: String = UpdateManager.find_asset_url(entry.get("release", {}), entry.get("asset_pattern", "*.AppImage"))
			if asset_url == "":
				install_feedback.text = "No release asset here matches this platform's pattern."
				install_button.disabled = false
				return
			var ok: bool = await UpdateManager.install_version(emulator_id, tag, asset_url)
			if is_instance_valid(install_feedback):
				install_feedback.text = "Installed and set active." if ok else "Install failed."
				if not ok and is_instance_valid(install_button):
					install_button.disabled = false
		)

	dialog.confirmed.connect(func(): dialog.queue_free())
	dialog.close_requested.connect(func(): dialog.queue_free())
	dialog.popup_centered()
