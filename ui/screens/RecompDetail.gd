extends Control
## A single recomp's page - deliberately mirrors GameDetail (hero banner,
## Play, gear into Settings) since a recomp is presented to the user as a
## game, not an emulator. There's no "Open Emulator" button here (compare
## GameDetail) - a recomp has no separate emulator to open on its own, it
## IS the thing that gets played. Version install/update management lives
## in RecompSettings' "Versions" tab instead of on this page, the same
## split GameDetail (Play only) keeps with GameSettings (per-game emulator+
## version picker) - this page only ever asks "is a version active, can I
## press Play", never "which version should that be".
##
## Same hero-aspect-ratio sizing as GameDetail (1920:620, SteamGridDB's
## actual hero ratio) for a consistent look between the two.
##
## Has a "Screenshots" tab (ScreenshotManager), same as GameDetail, keyed
## under the same "recomp:<id>" id already used for cover/hero art. No
## "Achievements" tab here, unlike GameDetail - RetroAchievements' catalog
## and every emulator with a native RA client are both essentially classic-
## console-only, so there's no realistic case where a self-contained native
## recomp would have an RA game id to show anything for.

const PluginTabHost := preload("res://ui/components/plugin_tab_host.gd")

const HERO_ASPECT_RATIO := 1920.0 / 620.0
const HERO_MAX_VIEWPORT_FRACTION := 0.4  ## see GameDetail._hero_height - same reasoning
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
@onready var gear_button: Button = %GearButton
@onready var meta_label: Label = %MetaLabel
@onready var status_label: Label = %StatusLabel
@onready var screenshots_tab_button: Button = %ScreenshotsTabButton
@onready var screenshots_pane: GridContainer = %ScreenshotsPane

var _recomp_id: String = ""
var _plugin_tabs = null  ## PluginTabHost - tabs registered by plugins, appended after Screenshots

func set_args(args: Dictionary) -> void:
	_recomp_id = args.get("recomp_id", "")

func _hero_height() -> float:
	var viewport_size := get_viewport_rect().size
	return min(viewport_size.x / HERO_ASPECT_RATIO, viewport_size.y * HERO_MAX_VIEWPORT_FRACTION)

func _ready() -> void:
	hero.custom_minimum_size.y = _hero_height()

	var recomp := EmulatorRegistry.get_emulator(_recomp_id)
	var shell := get_tree().get_first_node_in_group("shell")

	if recomp.is_empty():
		title_label.text = "Recomp not found"
		if shell:
			shell.set_title("Recomp")
		return

	if shell:
		shell.set_title(recomp.get("name", _recomp_id))
	title_label.text = recomp.get("name", "Untitled")
	hero_color.color = Color.html(_first_platform(recomp).get("accent_color", "#333333")).darkened(0.25)

	var hero_path := ArtManager.get_hero_path(_art_key())
	if hero_path != "":
		var image := Image.new()
		if image.load(hero_path) == OK:
			hero_art.texture = ImageTexture.create_from_image(image)
			hero_art.visible = true
			hero_scrim.visible = true

	_refresh_meta()

	play_button.pressed.connect(_on_play_pressed)
	gear_button.pressed.connect(func():
		Navigator.push("res://ui/screens/RecompSettings.tscn", {"recomp_id": _recomp_id})
	)
	screenshots_tab_button.pressed.connect(func(): _show_tab("screenshots"))
	_plugin_tabs = PluginTabHost.new(screenshots_tab_button.get_parent(), screenshots_pane.get_parent(), INACTIVE_TAB_COLOR)
	_plugin_tabs.populate(PluginRegistry.recomp_tabs_for(recomp), recomp, _show_tab)
	LaunchManager.screenshot_captured.connect(_on_screenshot_captured)
	_build_screenshots_pane()
	_show_tab("screenshots")

	play_button.grab_focus()

func _show_tab(tab: String) -> void:
	# Plugin tabs: the host shows the matching one (and hides the rest) and
	# returns its pane; null means `tab` is the built-in Screenshots tab.
	var plugin_pane: Control = _plugin_tabs.show_tab(tab) if _plugin_tabs != null else null
	screenshots_pane.visible = tab == "screenshots"
	screenshots_tab_button.add_theme_color_override("font_color", Color.WHITE if tab == "screenshots" else INACTIVE_TAB_COLOR)
	_grab_first_focusable(plugin_pane if plugin_pane != null else screenshots_pane)

## Depth-first search for the first visible, focusable control under
## `root` - same pattern as GameDetail/GameSettings/AppSettings/
## EmulatorDetail. Used when the Screenshots tab button is actually
## pressed (there's only the one tab, but the pane still starts empty/
## unfocused otherwise) and after a live rebuild.
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

func _first_platform(recomp: Dictionary) -> Dictionary:
	var platform_ids: Array = recomp.get("platforms", [])
	return EmulatorRegistry.get_platform(platform_ids[0]) if not platform_ids.is_empty() else {}

func _art_key() -> String:
	return "recomp:%s" % _recomp_id

func _refresh_meta() -> void:
	var recomp := EmulatorRegistry.get_emulator(_recomp_id)
	var platform_name: String = _first_platform(recomp).get("name", "?")
	var active: Variant = EmulatorRegistry.emulator_state.get(_recomp_id, {}).get("active", null)
	var last_played: Variant = EmulatorRegistry.last_played(_recomp_id)
	var when_text := "Never played" if last_played == null else "Last played %s" % last_played
	var version_text := "Not installed yet" if active == null else "Version %s" % active
	meta_label.text = "%s     Platform: %s     %s" % [when_text, platform_name, version_text]
	play_button.disabled = active == null
	play_button.tooltip_text = "" if active != null else "Install a version first - gear icon → Versions."

func _on_play_pressed() -> void:
	var result: Dictionary = LaunchManager.launch_emulator_standalone(_recomp_id, null, _art_key())
	if result.get("ok", false):
		EmulatorRegistry.record_played(_recomp_id)
		_refresh_meta()
	_show_result(result)

func _show_result(result: Dictionary) -> void:
	status_label.text = result.get("message", "")
	status_label.add_theme_color_override(
		"font_color",
		ACTIVE_COLOR if result.get("ok", false) else ERROR_COLOR
	)

# ======================== Screenshots ========================
# Same gallery UI as GameDetail's Screenshots tab, just keyed under
# "recomp:<id>" instead of a raw game id.

func _build_screenshots_pane() -> void:
	for child in screenshots_pane.get_children():
		child.queue_free()

	var paths: Array = ScreenshotManager.screenshots_for(_art_key())
	if paths.is_empty():
		var empty := Label.new()
		empty.text = "No screenshots yet - take one while playing (see Settings for the hotkey)."
		empty.add_theme_color_override("font_color", DOWNLOAD_COLOR)
		screenshots_pane.add_child(empty)
		return

	for path in paths:
		screenshots_pane.add_child(_make_screenshot_thumb(path))

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
	# See GameDetail._show_screenshot_dialog - same fix, same reason.
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
