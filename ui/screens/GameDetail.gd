extends Control
## A single game's page: hero banner, Play, Open Emulator (starts the
## assigned emulator on its own, no ROM, so the user can reach its settings
## without loading a game first - hidden for native/no-emulator games), and
## the gear icon into GameSettings. "Play" calls LaunchManager for real -
## it'll actually start the resolved emulator (or the native binary) if the
## binary exists on disk, and report exactly why if it doesn't (no version
## installed, binary missing, etc).
##
## The hero banner is sized at SteamGridDB's actual hero aspect ratio
## (1920:620) rather than cropped into some arbitrary fixed height - but
## capped to a fraction of the viewport's actual HEIGHT too (see
## _hero_height), not just derived from width - confirmed necessary for
## real: on a window that isn't itself roughly 1920:620-shaped, a
## width-only hero plus the actions/meta/status/tabs rows below it could
## add up to more than the whole viewport, squeezing the Achievements/
## Screenshots tab content down to zero height - loaded correctly (real
## data, real children) but completely invisible, not merely "taller than
## before".
##
## Below that, two tabs: "Achievements" (read-only RetroAchievements -
## AchievementsManager; see its header comment for why this can only ever
## mirror what already happened inside an RA-aware emulator, never unlock
## anything itself) and "Screenshots" (a gallery of whatever
## ScreenshotManager has saved for this game - see LaunchManager's
## screenshot hotkey for how those get taken in the first place).

const HERO_ASPECT_RATIO := 1920.0 / 620.0
const ACTIVE_COLOR := Color(0.4, 0.85, 0.5, 1)
const ERROR_COLOR := Color(0.9, 0.45, 0.45, 1)
const DOWNLOAD_COLOR := Color(0.6, 0.65, 0.7, 1)
const INACTIVE_TAB_COLOR := Color(0.6, 0.65, 0.7, 1)

@onready var hero: Control = %Hero
@onready var hero_color: ColorRect = %HeroColor
@onready var hero_art: TextureRect = %HeroArt
@onready var hero_scrim: ColorRect = %HeroScrim
@onready var title_label: Label = %TitleLabel
@onready var play_button: Button = %PlayButton
@onready var open_emulator_button: Button = %OpenEmulatorButton
@onready var gear_button: Button = %GearButton
@onready var meta_label: Label = %MetaLabel
@onready var status_label: Label = %StatusLabel
@onready var achievements_tab_button: Button = %AchievementsTabButton
@onready var screenshots_tab_button: Button = %ScreenshotsTabButton
@onready var achievements_pane: VBoxContainer = %AchievementsPane
@onready var screenshots_pane: GridContainer = %ScreenshotsPane

var _game_id: String = ""

const HERO_MAX_VIEWPORT_FRACTION := 0.4

func set_args(args: Dictionary) -> void:
	_game_id = args.get("game_id", "")

func _hero_height() -> float:
	var viewport_size := get_viewport_rect().size
	return min(viewport_size.x / HERO_ASPECT_RATIO, viewport_size.y * HERO_MAX_VIEWPORT_FRACTION)

func _ready() -> void:
	hero.custom_minimum_size.y = _hero_height()

	var game := LibraryScanner.get_game(_game_id)
	var shell := get_tree().get_first_node_in_group("shell")

	if game.is_empty():
		title_label.text = "Game not found"
		if shell:
			shell.set_title("Game")
		return

	var platform: Dictionary = EmulatorRegistry.get_platform(game.get("platform_id", ""))
	if shell:
		shell.set_title(game.get("title", "Game"))
	title_label.text = game.get("title", "Untitled")
	hero_color.color = Color.html(platform.get("accent_color", "#333333")).darkened(0.25)

	var hero_path := ArtManager.get_hero_path(_game_id)
	if hero_path != "":
		var image := Image.new()
		if image.load(hero_path) == OK:
			hero_art.texture = ImageTexture.create_from_image(image)
			hero_art.visible = true
			hero_scrim.visible = true

	var last_played: Variant = game.get("last_played", null)
	var playtime: float = game.get("playtime_hours", 0.0)
	var when_text := "Never played" if last_played == null else "Last played %s" % last_played
	var emulator_id: String = game.get("resolved_emulator_id", "")
	var emulator_text := "Native (no emulator)"
	if emulator_id != "":
		var emulator: Dictionary = EmulatorRegistry.get_emulator(emulator_id)
		var version: Variant = game.get("resolved_version", null)
		emulator_text = emulator.get("name", emulator_id)
		if version != null:
			emulator_text += " (%s)" % version
		else:
			emulator_text += " (default version)"
	meta_label.text = "%s     Platform: %s     Play time: %.1f hrs     Emulator: %s" % [
		when_text, platform.get("name", "?"), playtime, emulator_text
	]

	play_button.pressed.connect(_on_play_pressed.bind(game))
	open_emulator_button.visible = emulator_id != ""
	open_emulator_button.pressed.connect(_on_open_emulator_pressed.bind(game))
	gear_button.pressed.connect(func():
		Navigator.push("res://ui/screens/GameSettings.tscn", {"game_id": _game_id})
	)

	achievements_tab_button.pressed.connect(func(): _show_tab("achievements"))
	screenshots_tab_button.pressed.connect(func(): _show_tab("screenshots"))
	LaunchManager.screenshot_captured.connect(_on_screenshot_captured)
	_build_achievements_pane(int(game.get("retroachievements_game_id", 0)))
	_build_screenshots_pane()
	_show_tab("achievements")

	play_button.grab_focus()

func _on_play_pressed(game: Dictionary) -> void:
	var result: Dictionary = LaunchManager.launch(game)
	if result.get("ok", false):
		LibraryScanner.record_played(_game_id)
	_show_result(result)

func _on_open_emulator_pressed(game: Dictionary) -> void:
	_show_result(LaunchManager.launch_emulator_only(game))

func _show_result(result: Dictionary) -> void:
	status_label.text = result.get("message", "")
	status_label.add_theme_color_override(
		"font_color",
		ACTIVE_COLOR if result.get("ok", false) else ERROR_COLOR
	)

func _show_tab(tab: String) -> void:
	achievements_pane.visible = tab == "achievements"
	screenshots_pane.visible = tab == "screenshots"
	achievements_tab_button.add_theme_color_override("font_color", Color.WHITE if tab == "achievements" else INACTIVE_TAB_COLOR)
	screenshots_tab_button.add_theme_color_override("font_color", Color.WHITE if tab == "screenshots" else INACTIVE_TAB_COLOR)
	# Toggling .visible alone leaves focus on the tab button just pressed,
	# with nothing inside the now-visible pane for a controller to land on
	# - same bug/fix as every other sidebar/tab screen in this app
	# (GameSettings, AppSettings, EmulatorDetail, RecompSettings). Without
	# this, a controller could click into a tab but never navigate *within*
	# it - confirmed this was exactly why Achievements only responded to a
	# mouse wheel, not a controller, even once real rows existed.
	_grab_first_focusable(achievements_pane if tab == "achievements" else screenshots_pane)

## Depth-first search for the first visible, focusable control under
## `root` - see _show_tab and the pane-rebuild calls below.
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

# ======================== Achievements (read-only) ========================

func _build_achievements_pane(ra_game_id: int) -> void:
	for child in achievements_pane.get_children():
		child.queue_free()

	var loading := Label.new()
	loading.text = "Fetching achievements..."
	loading.add_theme_color_override("font_color", DOWNLOAD_COLOR)
	achievements_pane.add_child(loading)

	_populate_achievements(loading, ra_game_id)

func _populate_achievements(loading: Label, ra_game_id: int) -> void:
	var result: Dictionary = await AchievementsManager.fetch_achievements(ra_game_id)
	if not is_instance_valid(loading):
		return  # page was navigated away from while awaiting the network
	loading.queue_free()

	if not result.get("ok", false):
		var empty := Label.new()
		empty.text = result.get("message", "No achievements to show.")
		empty.add_theme_color_override("font_color", DOWNLOAD_COLOR)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		achievements_pane.add_child(empty)
		return

	var achievements: Array = result.get("achievements", [])
	var earned_count := 0
	for achievement in achievements:
		if achievement.get("earned", false):
			earned_count += 1

	var summary := Label.new()
	summary.text = "%d / %d earned" % [earned_count, achievements.size()]
	summary.add_theme_font_size_override("font_size", 18)
	achievements_pane.add_child(summary)

	for achievement in achievements:
		achievements_pane.add_child(_make_achievement_row(achievement))

	# The rows above didn't exist yet when _show_tab first ran (this is all
	# async) - if Achievements is still the active tab, grab focus now that
	# there's actually something focusable inside it.
	if achievements_pane.visible:
		_grab_first_focusable(achievements_pane)

## Returns a focusable Button (flat, custom content) rather than a plain
## HBoxContainer - confirmed necessary for real: a bare HBoxContainer has
## no focus_mode at all, so a controller's D-pad had nothing in this whole
## pane to land on, which was the actual reason Achievements only responded
## to a mouse wheel. Same trick GameTileFactory already uses for a tile's
## rich custom visual + real click/focus behavior - a flat Button hosting
## plain child Controls, not Button.text/.icon.
func _make_achievement_row(achievement: Dictionary) -> Button:
	var earned: bool = achievement.get("earned", false)

	var button := Button.new()
	button.flat = true
	button.focus_mode = Control.FOCUS_ALL
	button.custom_minimum_size = Vector2(0, 76)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(row)

	var badge := TextureRect.new()
	badge.custom_minimum_size = Vector2(64, 64)
	badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	badge.modulate = Color(1, 1, 1, 1) if earned else Color(1, 1, 1, 0.4)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(badge)
	_load_badge(badge, achievement.get("badge_url", ""))

	var text_col := VBoxContainer.new()
	text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(text_col)

	var title_row := HBoxContainer.new()
	title_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_col.add_child(title_row)
	var title_label2 := Label.new()
	title_label2.text = achievement.get("title", "?")
	title_label2.add_theme_color_override("font_color", Color.WHITE if earned else DOWNLOAD_COLOR)
	title_row.add_child(title_label2)
	var points_label := Label.new()
	points_label.text = "  (%d pts)" % achievement.get("points", 0)
	points_label.add_theme_color_override("font_color", DOWNLOAD_COLOR)
	title_row.add_child(points_label)

	var desc_label := Label.new()
	desc_label.text = achievement.get("description", "")
	desc_label.add_theme_color_override("font_color", DOWNLOAD_COLOR)
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_col.add_child(desc_label)

	return button

func _load_badge(badge: TextureRect, url: String) -> void:
	if url == "":
		return
	var bytes: PackedByteArray = await AchievementsManager.download_bytes(url)
	if not is_instance_valid(badge) or bytes.is_empty():
		return
	var image := Image.new()
	if image.load_png_from_buffer(bytes) == OK:
		badge.texture = ImageTexture.create_from_image(image)

# ======================== Screenshots ========================

func _build_screenshots_pane() -> void:
	for child in screenshots_pane.get_children():
		child.queue_free()

	var paths: Array = ScreenshotManager.screenshots_for(_game_id)
	if paths.is_empty():
		var empty := Label.new()
		empty.text = "No screenshots yet - take one while playing (see Settings for the hotkey)."
		empty.add_theme_color_override("font_color", DOWNLOAD_COLOR)
		screenshots_pane.add_child(empty)
		return

	for path in paths:
		screenshots_pane.add_child(_make_screenshot_thumb(path))

	# Same reasoning as the achievements rows - grab focus on the first
	# thumbnail only if Screenshots is still the active tab (this pane can
	# also get rebuilt live via _on_screenshot_captured while the other
	# tab is showing).
	if screenshots_pane.visible:
		_grab_first_focusable(screenshots_pane)

func _make_screenshot_thumb(path: String) -> Button:
	var thumb := Button.new()
	thumb.custom_minimum_size = Vector2(180, 101)
	thumb.text = ""
	var image := Image.new()
	if image.load(path) == OK:
		image.resize(180, 101, Image.INTERPOLATE_BILINEAR)
		thumb.icon = ImageTexture.create_from_image(image)
		thumb.expand_icon = true
	thumb.pressed.connect(func(): _show_screenshot_dialog(path))
	return thumb

func _show_screenshot_dialog(path: String) -> void:
	var dialog := AcceptDialog.new()
	dialog.title = path.get_file()
	dialog.size = Vector2i(900, 640)
	dialog.get_ok_button().text = "Close"
	add_child(dialog)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	dialog.add_child(vbox)

	var full := TextureRect.new()
	full.custom_minimum_size = Vector2(860, 500)
	# Without this, TextureRect's default expand_mode (EXPAND_KEEP_SIZE)
	# makes its OWN minimum size track the texture's native pixel
	# dimensions instead of custom_minimum_size above - confirmed necessary
	# for real: a real screenshot (1920x1080 or larger) blew the dialog up
	# way past the configured 900x640, since the TextureRect itself was
	# demanding native-resolution space from its container.
	full.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	full.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var image := Image.new()
	if image.load(path) == OK:
		full.texture = ImageTexture.create_from_image(image)
	vbox.add_child(full)

	var delete_button := Button.new()
	delete_button.text = "Delete"
	vbox.add_child(delete_button)
	delete_button.pressed.connect(func():
		ScreenshotManager.delete_screenshot(path)
		dialog.queue_free()
		_build_screenshots_pane()
	)

	dialog.confirmed.connect(func(): dialog.queue_free())
	dialog.close_requested.connect(func(): dialog.queue_free())
	dialog.popup_centered()

func _on_screenshot_captured(ok: bool, message: String) -> void:
	if ok:
		_build_screenshots_pane()
	status_label.text = message
	status_label.add_theme_color_override("font_color", ACTIVE_COLOR if ok else ERROR_COLOR)
