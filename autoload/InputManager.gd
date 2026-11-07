extends Node
## Tracks connected controllers and exposes basic glyph/brand info so UI
## can show the right button prompts later (A/B/X/Y vs PS glyphs, etc).
##
## Also patches a real Godot gotcha: the built-in "ui_accept"/"ui_cancel"
## actions that Button/focus navigation rely on ship with NO joypad bindings
## by default (confirmed via InputMap.action_get_events - keyboard-only;
## "ui_up"/"ui_down"/"ui_left"/"ui_right" DO have joypad bindings, which is
## why D-pad navigation worked but face buttons for select/back didn't).
## Added here, at the engine's normalized Xbox-layout button indices
## (JOY_BUTTON_A/B), so it works for any controller Godot's SDL mapping
## recognizes - not just the specific pad this was found on.

signal controller_connected(device_id: int, device_name: String)
signal controller_disconnected(device_id: int)

var connected_devices: Dictionary = {}  # device_id -> name

func _ready() -> void:
	_ensure_joypad_ui_bindings()
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	for device_id in Input.get_connected_joypads():
		_register_device(device_id)

func _ensure_joypad_ui_bindings() -> void:
	_add_joypad_binding_if_missing("ui_accept", JOY_BUTTON_A)
	_add_joypad_binding_if_missing("ui_cancel", JOY_BUTTON_B)

func _add_joypad_binding_if_missing(action: String, button_index: int) -> void:
	for event in InputMap.action_get_events(action):
		if event is InputEventJoypadButton and event.button_index == button_index:
			return
	var joypad_event := InputEventJoypadButton.new()
	joypad_event.button_index = button_index
	InputMap.action_add_event(action, joypad_event)

func _on_joy_connection_changed(device_id: int, connected: bool) -> void:
	if connected:
		_register_device(device_id)
	else:
		connected_devices.erase(device_id)
		controller_disconnected.emit(device_id)
		print("[InputManager] controller disconnected: id=%d" % device_id)

func _register_device(device_id: int) -> void:
	var device_name := Input.get_joy_name(device_id)
	connected_devices[device_id] = device_name
	controller_connected.emit(device_id, device_name)
	print("[InputManager] controller connected: id=%d name=%s" % [device_id, device_name])

func has_controller() -> bool:
	return connected_devices.size() > 0
