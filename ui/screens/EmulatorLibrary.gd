extends Control
## Mirrors Library.gd's grid, but for emulators instead of games - every
## emulator the user has configured, so it's easy to open one and see which
## version to use for a given game without having to go through a specific
## game's Settings page first. Reuses GameTileFactory as-is by handing it a
## synthetic {"id", "title"} dict - the factory only reads those two fields,
## and ArtManager keys emulator art under "emulator:<id>" (set by
## EmulatorDetail), so tiles pick up cover art automatically once it's set.
##
## Excludes 'recomp' integration_mode entries (EmulatorRegistry.is_recomp) -
## those are self-contained games with no ROM, not emulators you'd pick for
## something else, so they get their own "Recomps" section (RecompLibrary)
## instead of showing up here too.

const GameTileFactory = preload("res://ui/components/game_tile_factory.gd")
const TILE_WIDTH := 170.0
const FALLBACK_ACCENT := Color(0.35, 0.38, 0.42)

@onready var grid_scroll: ScrollContainer = %GridScroll
@onready var grid: GridContainer = %Grid

func _ready() -> void:
	var shell := get_tree().get_first_node_in_group("shell")
	if shell:
		shell.set_title("Emulators")
	_rebuild_grid()

func _rebuild_grid() -> void:
	for child in grid.get_children():
		child.queue_free()

	var first_tile: Button = null
	for emulator_id in EmulatorRegistry.emulators:
		if EmulatorRegistry.is_recomp(emulator_id):
			continue
		var emulator: Dictionary = EmulatorRegistry.get_emulator(emulator_id)
		var fake_game := {"id": _art_key(emulator_id), "title": emulator.get("name", emulator_id)}
		var tile := GameTileFactory.create(fake_game, _accent_for(emulator), TILE_WIDTH)
		GameTileFactory.attach_focus_feedback(tile, [grid_scroll])
		tile.pressed.connect(func():
			Navigator.push("res://ui/screens/EmulatorDetail.tscn", {"emulator_id": emulator_id})
		)
		grid.add_child(tile)
		if first_tile == null:
			first_tile = tile

	if first_tile != null:
		first_tile.grab_focus()

func _art_key(emulator_id: String) -> String:
	return "emulator:%s" % emulator_id

## Emulators don't have their own accent color - borrow the first platform
## they run on (platforms already have one), falling back to a neutral gray
## for an emulator with no platforms assigned yet.
func _accent_for(emulator: Dictionary) -> Color:
	var platform_ids: Array = emulator.get("platforms", [])
	if not platform_ids.is_empty():
		var platform: Dictionary = EmulatorRegistry.get_platform(platform_ids[0])
		if platform.has("accent_color"):
			return Color.html(platform["accent_color"]).darkened(0.1)
	return FALLBACK_ACCENT
