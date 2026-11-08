extends Node
## Central registry of everything a plugin can add to the launcher's UI:
## side-menu entries, full-screen pages, and tabs on the game / recomp
## detail pages. See docs/PLUGIN_API_PLAN.md.
##
## This is the foundation only. Nothing here loads plugins from disk yet
## (that is the plugin host, a later phase) - it is just the data structure
## and queries that Shell, Navigator, GameDetail and RecompDetail read from,
## so the same mechanism can serve built-in features and plugins.
##
## Every registration is tied to a plugin id so one call
## (remove_plugin) can take back everything a plugin added, which is what
## disabling or unloading a plugin will use.
##
## Definitions are plain Dictionaries holding Callables, so a plugin never
## needs to subclass anything to add UI:
##
##   menu item  {id, label, order?, visible_if?: Callable() -> bool,
##               open?: Callable(), page?: String}   (open or page required)
##   page       {id, title?, build: Callable(page_ctx, args) -> Control,
##               on_show?: Callable(page_ctx), on_hide?: Callable(page_ctx)}
##   game tab   {id, title, build: Callable(tab_ctx, game) -> Control,
##               order?, applies_to?: Callable(game) -> bool,
##               on_show?: Callable(tab_ctx, game), on_hide?: Callable(tab_ctx, game)}
##   recomp tab same as a game tab, with the recomp entry in place of game.

signal menu_changed
signal tabs_changed

const DEFAULT_ORDER := 50

const DemoPlugin := preload("res://plugins/examples/hello_plugin.gd")

var _menu_items: Dictionary = {}
var _pages: Dictionary = {}
var _game_tabs: Dictionary = {}
var _recomp_tabs: Dictionary = {}
var _demo = null  ## kept alive because the demo's Callables point at it

func _ready() -> void:
	# A throwaway example for trying the registries by hand, off by default:
	#   RETRL_PLUGIN_DEMO=1 godot --path .
	if OS.get_environment("RETRL_PLUGIN_DEMO") == "1":
		_demo = DemoPlugin.new()
		_demo.register(self)

# ============================= registration =============================

func add_menu_item(plugin_id: String, def: Dictionary) -> bool:
	var id := String(def.get("id", ""))
	var label := String(def.get("label", ""))
	if plugin_id == "" or id == "" or label == "":
		push_warning("[PluginRegistry] menu item needs a plugin id, id and label")
		return false
	var open_cb: Variant = def.get("open")
	var has_open: bool = open_cb is Callable
	if not has_open and String(def.get("page", "")) == "":
		push_warning("[PluginRegistry] menu item %s/%s needs 'open' or 'page'" % [plugin_id, id])
		return false
	_menu_items[_key(plugin_id, id)] = _entry(plugin_id, def, label)
	menu_changed.emit()
	return true

func add_page(plugin_id: String, def: Dictionary) -> bool:
	var id := String(def.get("id", ""))
	var builder: Variant = def.get("build")
	if plugin_id == "" or id == "" or not (builder is Callable):
		push_warning("[PluginRegistry] page needs a plugin id, id and a build Callable")
		return false
	_pages[_key(plugin_id, id)] = _entry(plugin_id, def, String(def.get("title", id)))
	return true

func add_game_tab(plugin_id: String, def: Dictionary) -> bool:
	return _add_tab(_game_tabs, plugin_id, def)

func add_recomp_tab(plugin_id: String, def: Dictionary) -> bool:
	return _add_tab(_recomp_tabs, plugin_id, def)

## Removes everything the plugin registered, in every registry.
func remove_plugin(plugin_id: String) -> void:
	var menu_changed_now := _erase_plugin(_menu_items, plugin_id)
	_erase_plugin(_pages, plugin_id)
	var tabs_changed_now := _erase_plugin(_game_tabs, plugin_id)
	tabs_changed_now = _erase_plugin(_recomp_tabs, plugin_id) or tabs_changed_now
	if menu_changed_now:
		menu_changed.emit()
	if tabs_changed_now:
		tabs_changed.emit()

# ================================ queries ================================

## Visible menu entries, ordered by `order` then label.
func menu_items() -> Array:
	var out: Array = []
	for entry in _menu_items.values():
		var visible_if: Variant = entry.get("visible_if")
		if visible_if is Callable and visible_if.is_valid() and not visible_if.call():
			continue
		out.append(entry)
	out.sort_custom(_sort_entries)
	return out

func get_page(plugin_id: String, page_id: String) -> Dictionary:
	return _pages.get(_key(plugin_id, page_id), {})

func game_tabs_for(game: Dictionary) -> Array:
	return _tabs_for(_game_tabs, game)

func recomp_tabs_for(recomp: Dictionary) -> Array:
	return _tabs_for(_recomp_tabs, recomp)

# ================================ internals ================================

func _add_tab(store: Dictionary, plugin_id: String, def: Dictionary) -> bool:
	var id := String(def.get("id", ""))
	var title := String(def.get("title", ""))
	var builder: Variant = def.get("build")
	if plugin_id == "" or id == "" or title == "" or not (builder is Callable):
		push_warning("[PluginRegistry] tab needs a plugin id, id, title and a build Callable")
		return false
	store[_key(plugin_id, id)] = _entry(plugin_id, def, title)
	tabs_changed.emit()
	return true

func _tabs_for(store: Dictionary, target: Dictionary) -> Array:
	var out: Array = []
	for entry in store.values():
		var applies_to: Variant = entry.get("applies_to")
		if applies_to is Callable:
			if not applies_to.is_valid() or not applies_to.call(target):
				continue
		out.append(entry)
	out.sort_custom(_sort_entries)
	return out

func _entry(plugin_id: String, def: Dictionary, sort_label: String) -> Dictionary:
	var entry := def.duplicate()
	entry["plugin_id"] = plugin_id
	entry["order"] = int(def.get("order", DEFAULT_ORDER))
	entry["sort_label"] = sort_label
	return entry

func _key(plugin_id: String, id: String) -> String:
	return "%s/%s" % [plugin_id, id]

func _erase_plugin(store: Dictionary, plugin_id: String) -> bool:
	var removed := false
	for key in store.keys():
		if store[key].get("plugin_id", "") == plugin_id:
			store.erase(key)
			removed = true
	return removed

func _sort_entries(a: Dictionary, b: Dictionary) -> bool:
	if a["order"] != b["order"]:
		return a["order"] < b["order"]
	return String(a["sort_label"]) < String(b["sort_label"])
