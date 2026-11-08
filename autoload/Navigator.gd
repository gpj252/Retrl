extends Node
## Swaps "page" scenes in and out of a host Control that Shell.gd registers
## at startup, keeping the top bar / side menu persistent across navigation
## instead of reloading the whole scene tree each time.
##
## A page is either a scene (push) or a plugin page registered with
## PluginRegistry (push_page). Both live on the same stack, so Back works the
## same for either.

const PageContext := preload("res://plugins/plugin_page_context.gd")

var _host: Control
var _stack: Array = []  # Array of {"path": String, "args": Dictionary} or {"plugin_id", "page_id", "args"}
var _current_page_def: Dictionary = {}
var _current_page_ctx: RefCounted = null

func register_host(host: Control) -> void:
	_host = host

func push(scene_path: String, args: Dictionary = {}) -> void:
	_stack.append({"path": scene_path, "args": args})
	_show(scene_path, args)

## Opens a plugin page registered through PluginRegistry.add_page. Returns
## false (and shows nothing) if no such page is registered.
func push_page(plugin_id: String, page_id: String, args: Dictionary = {}) -> bool:
	if PluginRegistry.get_page(plugin_id, page_id).is_empty():
		push_warning("[Navigator] no plugin page %s/%s" % [plugin_id, page_id])
		return false
	var entry := {"plugin_id": plugin_id, "page_id": page_id, "args": args}
	_stack.append(entry)
	_show_plugin_page(entry)
	return true

func pop() -> bool:
	if _stack.size() <= 1:
		return false
	_stack.pop_back()
	var top: Dictionary = _stack[-1]
	if top.has("page_id"):
		_show_plugin_page(top)
	else:
		_show(top["path"], top["args"])
	return true

func can_pop() -> bool:
	return _stack.size() > 1

func _show(scene_path: String, args: Dictionary) -> void:
	if _host == null:
		return
	_leave_current_page()
	for child in _host.get_children():
		child.queue_free()
	var packed: PackedScene = load(scene_path)
	var page: Node = packed.instantiate()
	if page.has_method("set_args"):
		page.call("set_args", args)
	_host.add_child(page)

func _show_plugin_page(entry: Dictionary) -> void:
	if _host == null:
		return
	_leave_current_page()
	for child in _host.get_children():
		child.queue_free()

	var def := PluginRegistry.get_page(entry["plugin_id"], entry["page_id"])
	var ctx := PageContext.new(entry["plugin_id"], entry["page_id"], entry["args"])
	var built: Variant = null
	var builder: Variant = def.get("build")
	if builder is Callable and builder.is_valid():
		built = builder.call(ctx, entry["args"])

	var page: Control
	if built is Control:
		page = built
	else:
		var failed := Label.new()
		failed.text = "This plugin page failed to load (%s). Press Back to return." % entry["plugin_id"]
		failed.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		failed.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		page = failed
	_host.add_child(page)
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_current_page_def = def
	_current_page_ctx = ctx
	var title := String(def.get("title", ""))
	if title != "":
		ctx.set_title(title)
	var on_show: Variant = def.get("on_show")
	if on_show is Callable and on_show.is_valid():
		on_show.call(ctx)

## Tells the page being replaced that it is going away (plugin pages only).
func _leave_current_page() -> void:
	if not _current_page_def.is_empty():
		var on_hide: Variant = _current_page_def.get("on_hide")
		if on_hide is Callable and on_hide.is_valid():
			on_hide.call(_current_page_ctx)
	_current_page_def = {}
	_current_page_ctx = null
