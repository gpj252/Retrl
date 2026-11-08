extends RefCounted
## Throwaway example showing every registration type. Only registered when
## the app is started with RETRL_PLUGIN_DEMO=1 (see PluginRegistry._ready).
## Gives a manual way to check the menu entry, the page, and the tabs on
## both game and recomp detail pages.
##
## The registry keeps a reference to this object for as long as it is
## registered, because the Callables below point at its methods.

const PLUGIN_ID := "demo"

func register(registry: Node) -> void:
	registry.add_page(PLUGIN_ID, {
		"id": "hello",
		"title": "Plugin Demo",
		"build": _build_page,
	})
	registry.add_menu_item(PLUGIN_ID, {
		"id": "hello",
		"label": "Plugin Demo",
		"page": "hello",
		"order": 60,
	})
	registry.add_game_tab(PLUGIN_ID, {
		"id": "info",
		"title": "Demo",
		"order": 90,
		"build": _build_game_tab,
	})
	registry.add_recomp_tab(PLUGIN_ID, {
		"id": "info",
		"title": "Demo",
		"order": 90,
		"build": _build_recomp_tab,
	})

func _build_page(_ctx, _args: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	var label := Label.new()
	label.text = "Hello from a plugin page. Press Back to return."
	box.add_child(label)
	var button := Button.new()
	button.text = "A focusable button"
	box.add_child(button)
	button.call_deferred("grab_focus")
	return box

func _build_game_tab(_ctx, game: Dictionary) -> Control:
	return _tab_content("Demo tab for: %s" % game.get("title", "?"))

func _build_recomp_tab(_ctx, recomp: Dictionary) -> Control:
	return _tab_content("Demo recomp tab for: %s" % recomp.get("name", "?"))

func _tab_content(text: String) -> Control:
	var box := VBoxContainer.new()
	var label := Label.new()
	label.text = text
	box.add_child(label)
	var button := Button.new()
	button.text = "Focusable"
	box.add_child(button)
	return box
