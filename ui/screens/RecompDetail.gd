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

const HERO_ASPECT_RATIO := 1920.0 / 620.0

@onready var hero: Control = %Hero
@onready var hero_color: ColorRect = %HeroColor
@onready var hero_art: TextureRect = %HeroArt
@onready var hero_scrim: ColorRect = %HeroScrim
@onready var title_label: Label = %TitleLabel
@onready var play_button: Button = %PlayButton
@onready var gear_button: Button = %GearButton
@onready var meta_label: Label = %MetaLabel
@onready var status_label: Label = %StatusLabel

var _recomp_id: String = ""

func set_args(args: Dictionary) -> void:
	_recomp_id = args.get("recomp_id", "")

func _ready() -> void:
	hero.custom_minimum_size.y = get_viewport_rect().size.x / HERO_ASPECT_RATIO

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

	play_button.grab_focus()

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
	var result: Dictionary = LaunchManager.launch_emulator_standalone(_recomp_id)
	if result.get("ok", false):
		EmulatorRegistry.record_played(_recomp_id)
		_refresh_meta()
	_show_result(result)

func _show_result(result: Dictionary) -> void:
	status_label.text = result.get("message", "")
	status_label.add_theme_color_override(
		"font_color",
		Color(0.4, 0.85, 0.5, 1) if result.get("ok", false) else Color(0.9, 0.45, 0.45, 1)
	)
