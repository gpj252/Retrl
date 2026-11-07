class_name GameTileFactory
extends RefCounted
## Builds a portrait game tile (Button) in code - shared by Home's carousel
## and the Library grid so they stay visually consistent. The art region is
## fixed at a 2:3 ratio (matching SteamGridDB's 600x900 portrait grids) and
## cropped-to-fill rather than stretched, so real cover art never looks
## warped regardless of its exact source resolution. Falls back to a flat
## platform-accent-colored rect with the title's first letter when a game
## has no cover art cached.

const ASPECT_RATIO := 1.5  # height = width * 1.5, i.e. 2:3 portrait
const CAPTION_HEIGHT := 44.0

## width is the tile's width; height (art + caption strip) is derived from
## the fixed 2:3 art ratio, so every tile stays visually consistent.
static func create(game: Dictionary, accent: Color, width: float) -> Button:
	var art_height := width * ASPECT_RATIO
	var tile_size := Vector2(width, art_height + CAPTION_HEIGHT)
	var art_height_ratio := art_height / tile_size.y

	var tile := Button.new()
	tile.custom_minimum_size = tile_size
	tile.theme_type_variation = "GameTileButton"
	tile.focus_mode = Control.FOCUS_ALL
	tile.text = ""

	var title: String = game.get("title", "?")
	var art_path: String = ArtManager.get_art_path(game.get("id", ""))

	if art_path != "":
		var image := Image.new()
		if image.load(art_path) == OK:
			var art := TextureRect.new()
			art.texture = ImageTexture.create_from_image(image)
			art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			art.clip_contents = true
			art.mouse_filter = Control.MOUSE_FILTER_IGNORE
			art.set_anchors_preset(Control.PRESET_TOP_WIDE)
			art.anchor_bottom = art_height_ratio
			art.offset_bottom = 0
			tile.add_child(art)
		else:
			art_path = ""  # corrupt/unreadable file - fall back below

	if art_path == "":
		var art := ColorRect.new()
		art.color = accent
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art.set_anchors_preset(Control.PRESET_TOP_WIDE)
		art.anchor_bottom = art_height_ratio
		art.offset_bottom = 0
		tile.add_child(art)

		var initials := Label.new()
		initials.text = title.substr(0, 1).to_upper() if title.length() > 0 else "?"
		initials.mouse_filter = Control.MOUSE_FILTER_IGNORE
		initials.add_theme_font_size_override("font_size", int(width * 0.24))
		initials.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
		initials.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		initials.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		initials.set_anchors_preset(Control.PRESET_TOP_WIDE)
		initials.anchor_bottom = art_height_ratio
		initials.offset_bottom = 0
		tile.add_child(initials)

	var caption := Label.new()
	caption.text = title
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caption.clip_text = true
	caption.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	caption.anchor_top = art_height_ratio
	caption.offset_top = 4
	caption.offset_left = 6
	caption.offset_right = -6
	tile.add_child(caption)

	return tile

## Wires the Steam-style "grow + white border" focus feedback. Call after
## create(); scroll_containers are whichever ScrollContainer ancestors
## should auto-scroll to keep the focused tile visible (pass 1-2 of them).
static func attach_focus_feedback(tile: Button, scroll_containers: Array) -> void:
	tile.focus_entered.connect(func():
		tile.pivot_offset = tile.size / 2.0
		tile.z_index = 1
		var tween := tile.create_tween()
		tween.tween_property(tile, "scale", Vector2(1.08, 1.08), 0.1).set_ease(Tween.EASE_OUT)
		for scroll in scroll_containers:
			if scroll != null:
				scroll.ensure_control_visible(tile)
	)
	tile.focus_exited.connect(func():
		tile.z_index = 0
		var tween := tile.create_tween()
		tween.tween_property(tile, "scale", Vector2.ONE, 0.1).set_ease(Tween.EASE_OUT)
	)
