extends RefCounted
## Adds plugin-registered tabs to a detail page (GameDetail / RecompDetail).
##
## The page keeps its own built-in tabs exactly as before; this only appends
## one button per plugin tab to the page's tab row and one pane per plugin tab
## next to the page's other panes, and tells the page when one is picked.
## A plugin tab's content is built lazily the first time it is shown, and a
## tab that fails to build shows a short message instead of breaking the page.
##
## Usage from a detail page:
##   _plugin_tabs = PluginTabHost.new(tab_row, pane_parent, INACTIVE_TAB_COLOR)
##   _plugin_tabs.populate(PluginRegistry.game_tabs_for(game), game, _show_tab)
## and from the page's own _show_tab(tab):
##   var plugin_pane = _plugin_tabs.show_tab(tab)   # null for built-in tabs

const TabContext := preload("res://plugins/plugin_tab_context.gd")

var _bar: Container
var _pane_parent: Control
var _inactive_color: Color
var _target: Dictionary = {}
var _on_selected: Callable
var _entries: Dictionary = {}  # tab key -> {button, pane, def, ctx, built}
var _active_key: String = ""

func _init(bar: Container, pane_parent: Control, inactive_color: Color) -> void:
	_bar = bar
	_pane_parent = pane_parent
	_inactive_color = inactive_color

static func tab_key(def: Dictionary) -> String:
	return "%s/%s" % [def["plugin_id"], def["id"]]

## Creates a button and an (empty, hidden) pane for each tab definition.
## `on_selected` is called with the tab key when its button is pressed.
func populate(tab_defs: Array, target: Dictionary, on_selected: Callable) -> void:
	_target = target
	_on_selected = on_selected
	for def in tab_defs:
		var key := tab_key(def)
		var button := Button.new()
		button.text = String(def["title"])
		button.focus_mode = Control.FOCUS_ALL
		button.add_theme_color_override("font_color", _inactive_color)
		button.pressed.connect(func(): _on_selected.call(key))
		_bar.add_child(button)

		var pane := VBoxContainer.new()
		pane.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pane.add_theme_constant_override("separation", 8)
		pane.visible = false
		_pane_parent.add_child(pane)

		var ctx := TabContext.new(def["plugin_id"], def["id"], target)
		ctx.refresh_requested.connect(func(): _rebuild(key))
		_entries[key] = {"button": button, "pane": pane, "def": def, "ctx": ctx, "built": false}

func has_tab(key: String) -> bool:
	return _entries.has(key)

## Shows the plugin tab `key` (building it on first use) and hides every other
## plugin tab. Returns the shown pane so the caller can move focus into it, or
## null when `key` is not a plugin tab (the caller's own tab handling applies).
func show_tab(key: String) -> Control:
	if _active_key != "" and _active_key != key:
		_call_hook(_active_key, "on_hide")
	var shown: Control = null
	for entry_key in _entries.keys():
		var entry: Dictionary = _entries[entry_key]
		var active: bool = entry_key == key
		entry["pane"].visible = active
		entry["button"].add_theme_color_override("font_color", Color.WHITE if active else _inactive_color)
		if active:
			if not entry["built"]:
				_build(entry)
			shown = entry["pane"]
	if shown != null:
		if _active_key != key:
			_call_hook(key, "on_show")
		_active_key = key
	else:
		_active_key = ""
	return shown

## First visible, focusable control under `root` (depth-first), or null.
static func find_first_focusable(root: Node) -> Control:
	for child in root.get_children():
		if child is Control:
			var control: Control = child
			if not control.visible:
				continue
			if control.focus_mode != Control.FOCUS_NONE:
				return control
			var nested := find_first_focusable(control)
			if nested != null:
				return nested
	return null

func _build(entry: Dictionary) -> void:
	entry["built"] = true
	var pane: Control = entry["pane"]
	for child in pane.get_children():
		child.queue_free()
	var content: Variant = null
	var builder: Variant = entry["def"].get("build")
	if builder is Callable and builder.is_valid():
		content = builder.call(entry["ctx"], _target)
	if content is Control:
		pane.add_child(content)
	else:
		var failed := Label.new()
		failed.text = "This tab failed to load (plugin: %s)." % entry["def"]["plugin_id"]
		failed.add_theme_color_override("font_color", _inactive_color)
		pane.add_child(failed)

func _rebuild(key: String) -> void:
	if not _entries.has(key):
		return
	var entry: Dictionary = _entries[key]
	_build(entry)
	if key == _active_key:
		var found := find_first_focusable(entry["pane"])
		if found != null:
			found.grab_focus()

func _call_hook(key: String, hook: String) -> void:
	if not _entries.has(key):
		return
	var entry: Dictionary = _entries[key]
	var callback: Variant = entry["def"].get(hook)
	if callback is Callable and callback.is_valid():
		callback.call(entry["ctx"], _target)
