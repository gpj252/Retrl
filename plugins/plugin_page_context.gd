extends RefCounted
## Handed to a plugin page's `build` / `on_show` / `on_hide` callbacks.

var plugin_id: String
var page_id: String
var args: Dictionary

func _init(p_plugin_id: String, p_page_id: String, p_args: Dictionary) -> void:
	plugin_id = p_plugin_id
	page_id = p_page_id
	args = p_args

## Changes the title shown in the shell's top bar.
func set_title(text: String) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var shell := tree.get_first_node_in_group("shell")
	if shell != null and shell.has_method("set_title"):
		shell.call("set_title", text)

## Leaves this page (same as the Back button).
func back() -> void:
	Navigator.pop()
