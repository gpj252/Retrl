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
## (1920:620) rather than cropped into some arbitrary fixed height - it's
## taller than before, so everything below it sits lower on the page now.

const HERO_ASPECT_RATIO := 1920.0 / 620.0

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

var _game_id: String = ""

func set_args(args: Dictionary) -> void:
	_game_id = args.get("game_id", "")

func _ready() -> void:
	hero.custom_minimum_size.y = get_viewport_rect().size.x / HERO_ASPECT_RATIO

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
		Color(0.4, 0.85, 0.5, 1) if result.get("ok", false) else Color(0.9, 0.45, 0.45, 1)
	)
