extends Control
## Full library browser: search box, platform tabs (+ "All"), grid of every
## matching game. This is where cross-platform browsing with structure
## lives - Home is deliberately just the cross-platform recency carousel.
##
## Recomps tracked directly (EmulatorRegistry.recomp_ids) aren't in
## LibraryScanner's game list at all - they're presented as games here too
## (see _recomps_for_platform), merged in only on whichever specific
## platform tab(s) they're assigned to (almost always "Native
## Recompilations"), same as any Quiver-scanned recomp already there. "All"
## stays LibraryScanner.games as-is, unchanged.

const GameTileFactory = preload("res://ui/components/game_tile_factory.gd")
const TILE_WIDTH := 170.0
const ACTIVE_TAB_COLOR := Color(1, 1, 1, 1)
const INACTIVE_TAB_COLOR := Color(0.6, 0.65, 0.7, 1)

@onready var search_box: LineEdit = %SearchBox
@onready var tabs: HBoxContainer = %Tabs
@onready var grid_scroll: ScrollContainer = %GridScroll
@onready var grid: GridContainer = %Grid

var _current_platform_id: String = ""  # "" = All
var _tab_buttons: Dictionary = {}  # platform_id ("" for All) -> Button

func _ready() -> void:
	var shell := get_tree().get_first_node_in_group("shell")
	if shell:
		shell.set_title("Library")
	search_box.text_changed.connect(func(_t): _rebuild_grid())
	_build_tabs()
	_rebuild_grid()

func _build_tabs() -> void:
	for child in tabs.get_children():
		child.queue_free()
	_tab_buttons.clear()

	_add_tab("", "All (%d)" % LibraryScanner.games.size())
	for platform_id in EmulatorRegistry.platforms:
		var count := LibraryScanner.games_for_platform(platform_id).size() + _recomps_for_platform(platform_id).size()
		if count == 0:
			continue
		var platform: Dictionary = EmulatorRegistry.get_platform(platform_id)
		_add_tab(platform_id, "%s (%d)" % [platform.get("name", platform_id), count])

	_refresh_tab_styles()

func _add_tab(platform_id: String, label: String) -> void:
	var button := Button.new()
	button.text = label
	button.focus_mode = Control.FOCUS_ALL
	button.pressed.connect(func():
		_current_platform_id = platform_id
		_refresh_tab_styles()
		_rebuild_grid()
	)
	tabs.add_child(button)
	_tab_buttons[platform_id] = button

func _refresh_tab_styles() -> void:
	for platform_id in _tab_buttons:
		var button: Button = _tab_buttons[platform_id]
		var is_active: bool = platform_id == _current_platform_id
		button.add_theme_color_override("font_color", ACTIVE_TAB_COLOR if is_active else INACTIVE_TAB_COLOR)
		button.add_theme_color_override("font_focus_color", ACTIVE_TAB_COLOR)

func _rebuild_grid() -> void:
	for child in grid.get_children():
		child.queue_free()

	var query := search_box.text.to_lower()
	var source: Array[Dictionary] = []
	if _current_platform_id != "":
		source = LibraryScanner.games_for_platform(_current_platform_id)
		source.append_array(_recomps_for_platform(_current_platform_id))
	else:
		source = LibraryScanner.games

	var first_tile: Button = null
	for game in source:
		var title: String = game.get("title", "")
		if query != "" and query not in title.to_lower():
			continue
		var platform: Dictionary = EmulatorRegistry.get_platform(game.get("platform_id", ""))
		var accent := Color.html(platform.get("accent_color", "#444444"))
		var tile := GameTileFactory.create(game, accent, TILE_WIDTH)
		GameTileFactory.attach_focus_feedback(tile, [grid_scroll])
		var recomp_id: String = game.get("_recomp_id", "")
		tile.pressed.connect(func():
			if recomp_id != "":
				Navigator.push("res://ui/screens/RecompDetail.tscn", {"recomp_id": recomp_id})
			else:
				Navigator.push("res://ui/screens/GameDetail.tscn", {"game_id": game.get("id", "")})
		)
		grid.add_child(tile)
		if first_tile == null:
			first_tile = tile

	if first_tile != null:
		first_tile.grab_focus()

## Recomps presented as fake {"id", "title", "platform_id", "_recomp_id"}
## game dicts, scoped to whichever platform(s) this one belongs to - the
## same shape GameTileFactory/_rebuild_grid already expect, so no special-
## casing is needed there beyond branching on "_recomp_id" in the press
## handler. "id" is the "recomp:<id>" art key (RecompSettings' Art tab),
## so a recomp's cover art picks up here automatically, same as a real
## game's would.
func _recomps_for_platform(platform_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for recomp_id in EmulatorRegistry.recomp_ids():
		var recomp: Dictionary = EmulatorRegistry.get_emulator(recomp_id)
		if platform_id in recomp.get("platforms", []):
			result.append({
				"id": "recomp:%s" % recomp_id,
				"title": recomp.get("name", recomp_id),
				"platform_id": platform_id,
				"_recomp_id": recomp_id,
			})
	return result
