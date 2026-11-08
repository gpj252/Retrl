extends Control
## Persistent frame around every page: top bar (title + clock), the
## slide-out side menu, and global Back/Menu input. Pages are swapped in
## and out of %PageHost by the Navigator autoload so this frame never
## reloads between screens.
##
## Side menu only includes items we actually implement - no Store/Friends/
## Media/Downloads/Power like the Steam reference, since this launcher has
## no store or social features. Home / Library / Emulators / Recomps /
## Settings / Quit.
##
## Also owns the "playing" state: while LaunchManager reports a game/emulator
## running, the whole page tree is paused (get_tree().paused - Godot skips
## _process/_input/_gui_input for every PAUSABLE node, which covers side-menu
## buttons and every page's focused control without touching each screen
## individually) and a full-screen overlay is shown so there's nothing left
## to interact with even if a stray input slips through. The window is also
## minimized as a best-effort nudge for the compositor to hand focus to the
## emulator's own window - this is gamescope/SteamOS-session behavior that
## can't be exercised outside that environment, so treat it as best-effort,
## not confirmed.

@onready var menu_button: Button = %MenuButton
@onready var title_label: Label = %TitleLabel
@onready var clock_label: Label = %ClockLabel
@onready var page_host: Control = %PageHost
@onready var side_menu: Control = %SideMenu
@onready var menu_items: VBoxContainer = %MenuItems
@onready var playing_overlay: Control = %PlayingOverlay
@onready var playing_label: Label = %PlayingLabel
@onready var screenshot_feedback_label: Label = %ScreenshotFeedbackLabel

var _window_mode_before_play: int = -1

func _ready() -> void:
	add_to_group("shell")
	Navigator.register_host(page_host)
	menu_button.pressed.connect(toggle_side_menu)
	_build_side_menu()
	Navigator.push("res://ui/screens/Home.tscn")
	_update_clock()
	LaunchManager.game_started.connect(_on_game_started)
	LaunchManager.game_stopped.connect(_on_game_stopped)
	# Connected signal handlers still fire while get_tree().paused is true
	# (pause only gates per-frame _process/_input, not emitted signals) -
	# same reason _on_game_started/_on_game_stopped already work despite
	# Shell itself being paused. This is the only feedback the screenshot
	# hotkey gets while the Playing overlay is up.
	LaunchManager.screenshot_captured.connect(_on_screenshot_captured)

func _on_game_started(label: String) -> void:
	close_side_menu()
	playing_label.text = "Playing %s\n\nThe launcher is paused - it'll come back when you close this." % label
	screenshot_feedback_label.text = ""
	playing_overlay.visible = true
	_window_mode_before_play = get_window().mode
	get_window().mode = Window.MODE_MINIMIZED
	get_tree().paused = true

func _on_game_stopped() -> void:
	get_tree().paused = false
	if _window_mode_before_play != -1:
		get_window().mode = _window_mode_before_play
		_window_mode_before_play = -1
	playing_overlay.visible = false

func _on_screenshot_captured(ok: bool, message: String) -> void:
	if not playing_overlay.visible:
		return
	screenshot_feedback_label.text = message
	screenshot_feedback_label.add_theme_color_override(
		"font_color",
		Color(0.4, 0.85, 0.5, 1) if ok else Color(0.9, 0.45, 0.45, 1)
	)

func _process(_delta: float) -> void:
	_update_clock()

func _update_clock() -> void:
	clock_label.text = Time.get_time_string_from_system().substr(0, 5)

## Pages call this (Shell is their closest ancestor) to update the header.
func set_title(text: String) -> void:
	title_label.text = text

func _build_side_menu() -> void:
	for child in menu_items.get_children():
		child.queue_free()
	_add_menu_item("Home", func():
		Navigator.push("res://ui/screens/Home.tscn")
		close_side_menu()
	)
	_add_menu_item("Library", func():
		Navigator.push("res://ui/screens/Library.tscn")
		close_side_menu()
	)
	_add_menu_item("Emulators", func():
		Navigator.push("res://ui/screens/EmulatorLibrary.tscn")
		close_side_menu()
	)
	_add_menu_item("Recomps", func():
		Navigator.push("res://ui/screens/RecompLibrary.tscn")
		close_side_menu()
	)
	_add_menu_item("Settings", func():
		Navigator.push("res://ui/screens/AppSettings.tscn")
		close_side_menu()
	)
	_add_menu_item("Quit", func():
		get_tree().quit()
	)

func _add_menu_item(label: String, on_pressed: Callable) -> void:
	var button := Button.new()
	button.text = label
	button.focus_mode = Control.FOCUS_ALL
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.pressed.connect(on_pressed)
	menu_items.add_child(button)

func toggle_side_menu() -> void:
	if side_menu.visible:
		close_side_menu()
	else:
		open_side_menu()

func open_side_menu() -> void:
	side_menu.visible = true
	if menu_items.get_child_count() > 0:
		menu_items.get_child(0).grab_focus()

func close_side_menu() -> void:
	side_menu.visible = false

func _unhandled_input(event: InputEvent) -> void:
	var is_menu_press: bool = (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_M) \
		or (event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_START)
	if is_menu_press:
		toggle_side_menu()
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("ui_cancel"):
		if side_menu.visible:
			close_side_menu()
			get_viewport().set_input_as_handled()
		elif Navigator.can_pop():
			Navigator.pop()
			get_viewport().set_input_as_handled()
