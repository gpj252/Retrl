extends Control
## Library for recomps - self-contained native ports with no ROM, tracked
## via the same git-releases machinery as any emulator (EmulatorRegistry.
## recomp_ids) but presented to the user as games: one tile per recomp,
## opening RecompDetail (a GameDetail-style page: hero banner, Play, gear
## into RecompSettings) rather than EmulatorDetail. Mirrors EmulatorLibrary's
## grid, but art is kept under its own "recomp:<id>" namespace (cover AND
## hero, like a real game) rather than reusing "emulator:<id>" (cover only)
## - a recomp having its own section means it shouldn't look half-set-up
## just because someone set emulator art for it before this section existed.

const GameTileFactory = preload("res://ui/components/game_tile_factory.gd")
const TILE_WIDTH := 170.0
const FALLBACK_ACCENT := Color(0.35, 0.38, 0.42)

@onready var grid_scroll: ScrollContainer = %GridScroll
@onready var grid: GridContainer = %Grid
@onready var empty_label: Label = %EmptyLabel

func _ready() -> void:
	var shell := get_tree().get_first_node_in_group("shell")
	if shell:
		shell.set_title("Recomps")
	_rebuild_grid()

func _rebuild_grid() -> void:
	for child in grid.get_children():
		child.queue_free()

	var recomp_ids: Array = EmulatorRegistry.recomp_ids()
	empty_label.visible = recomp_ids.is_empty()
	if recomp_ids.is_empty():
		return

	var first_tile: Button = null
	for recomp_id in recomp_ids:
		var recomp: Dictionary = EmulatorRegistry.get_emulator(recomp_id)
		var fake_game := {"id": _art_key(recomp_id), "title": recomp.get("name", recomp_id)}
		var tile := GameTileFactory.create(fake_game, _accent_for(recomp), TILE_WIDTH)
		GameTileFactory.attach_focus_feedback(tile, [grid_scroll])
		tile.pressed.connect(func():
			Navigator.push("res://ui/screens/RecompDetail.tscn", {"recomp_id": recomp_id})
		)
		grid.add_child(tile)
		if first_tile == null:
			first_tile = tile

	if first_tile != null:
		first_tile.grab_focus()

## Same "recomp:<id>" art-key convention RecompDetail/RecompSettings use.
func _art_key(recomp_id: String) -> String:
	return "recomp:%s" % recomp_id

## Recomps don't have their own accent color - borrow the first platform
## they run on, same fallback approach as EmulatorLibrary._accent_for.
func _accent_for(recomp: Dictionary) -> Color:
	var platform_ids: Array = recomp.get("platforms", [])
	if not platform_ids.is_empty():
		var platform: Dictionary = EmulatorRegistry.get_platform(platform_ids[0])
		if platform.has("accent_color"):
			return Color.html(platform["accent_color"]).darkened(0.1)
	return FALLBACK_ACCENT
