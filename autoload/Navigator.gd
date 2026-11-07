extends Node
## Swaps "page" scenes in and out of a host Control that Shell.gd registers
## at startup, keeping the top bar / side menu persistent across navigation
## instead of reloading the whole scene tree each time.

var _host: Control
var _stack: Array = []  # Array of {"path": String, "args": Dictionary}

func register_host(host: Control) -> void:
	_host = host

func push(scene_path: String, args: Dictionary = {}) -> void:
	_stack.append({"path": scene_path, "args": args})
	_show(scene_path, args)

func pop() -> bool:
	if _stack.size() <= 1:
		return false
	_stack.pop_back()
	var top: Dictionary = _stack[-1]
	_show(top["path"], top["args"])
	return true

func can_pop() -> bool:
	return _stack.size() > 1

func _show(scene_path: String, args: Dictionary) -> void:
	if _host == null:
		return
	for child in _host.get_children():
		child.queue_free()
	var packed: PackedScene = load(scene_path)
	var page: Node = packed.instantiate()
	if page.has_method("set_args"):
		page.call("set_args", args)
	_host.add_child(page)
