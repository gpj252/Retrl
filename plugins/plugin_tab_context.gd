extends RefCounted
## Handed to a plugin's tab `build` / `on_show` / `on_hide` callbacks - its
## only handle to the tab it owns. `target` is the game (or recomp) entry the
## tab is showing.

signal refresh_requested

var plugin_id: String
var tab_id: String
var target: Dictionary

func _init(p_plugin_id: String, p_tab_id: String, p_target: Dictionary) -> void:
	plugin_id = p_plugin_id
	tab_id = p_tab_id
	target = p_target

## Ask the host to rebuild this tab's content (for example after async data
## arrives or a setting changes).
func request_refresh() -> void:
	refresh_requested.emit()
