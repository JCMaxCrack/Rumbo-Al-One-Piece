class_name GraphicsOptions
extends Control
## "Options" panel (scenes/ui/graphics_options.tscn), used from the main menu and the pause menu.
## Quality preset (Bajo / Medio / Alto), render resolution slider, full screen, FPS counter,
## language (Preferences), the controls (ControlsMenu, to change keys and gamepad buttons) and
## gesture control with the camera (GestureControl; made in code, under the FPS check).
## Every change is applied at once and saved by GraphicsSettings / Preferences.

signal closed

const RENDERER_NAMES := {"forward_plus": "Forward+", "mobile": "Mobile", "gl_compatibility": "Compatibility (OpenGL)"}

@onready var preset_button: OptionButton = $Panel/VBox/PresetRow/PresetButton
@onready var scale_slider: HSlider = $Panel/VBox/ScaleRow/ScaleSlider
@onready var scale_label: Label = $Panel/VBox/ScaleRow/ScaleValue
@onready var fps_check: CheckBox = $Panel/VBox/FpsCheck
@onready var fullscreen_check: CheckBox = $Panel/VBox/FullscreenCheck
@onready var info_label: Label = $Panel/VBox/Info
@onready var back_button: Button = $Panel/VBox/BackButton
@onready var language_button: OptionButton = $Panel/VBox/LanguageRow/LanguageButton
@onready var controls_menu: ControlsMenu = $ControlsMenu

var gesture_check: CheckBox
var gesture_status: Label


func _ready() -> void:
	language_button.clear()
	for code in Preferences.LANGUAGES:
		language_button.add_item(Preferences.LANGUAGES[code])
	controls_menu.closed.connect(_on_controls_menu_closed)
	gesture_check = CheckBox.new()
	gesture_check.text = "Gesture control (camera)"
	gesture_check.toggled.connect(GestureControl.set_enabled)
	$Panel/VBox.add_child(gesture_check)
	$Panel/VBox.move_child(gesture_check, fps_check.get_index() + 1)
	gesture_status = Label.new()
	gesture_status.add_theme_font_size_override("font_size", 14)
	gesture_status.modulate = Color(0.8, 0.85, 0.9)
	gesture_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	$Panel/VBox.add_child(gesture_status)
	$Panel/VBox.move_child(gesture_status, gesture_check.get_index() + 1)
	GestureControl.status_changed.connect(func(_t): _refresh_gesture())


func open() -> void:
	visible = true
	_refresh()
	preset_button.grab_focus()


func close() -> void:
	if controls_menu.visible:
		controls_menu.close()
		return
	visible = false
	closed.emit()


func _refresh() -> void:
	preset_button.select(GraphicsSettings.preset)
	scale_slider.set_value_no_signal(roundf(GraphicsSettings.render_scale * 100.0))
	scale_label.text = "%d %%" % int(scale_slider.value)
	fps_check.set_pressed_no_signal(GraphicsSettings.show_fps)
	fullscreen_check.set_pressed_no_signal(GraphicsSettings.fullscreen)
	fullscreen_check.visible = GraphicsSettings.can_change_window()
	language_button.select(Preferences.LANGUAGES.keys().find(Preferences.language))
	_refresh_gesture()
	for i in preset_button.item_count:
		preset_button.set_item_text(i, tr(GraphicsSettings.NAMES[i]))
	var r := GraphicsSettings.renderer()
	info_label.text = "%s\n%s: %s" % [tr(GraphicsSettings.settings().description), tr("Renderer"), tr(RENDERER_NAMES.get(r, r))]


func _refresh_gesture() -> void:
	gesture_check.set_pressed_no_signal(Preferences.gesture_control)
	gesture_status.text = GestureControl.status_text() + "\n" + tr("Open palm: walk  ·  Hand to a side: turn  ·  Fist: punch  ·  Two fingers: jump  ·  Index finger: talk  ·  Thumb up: skill")


func _on_preset_button_item_selected(index: int) -> void:
	GraphicsSettings.set_preset(index)
	_refresh()


func _on_scale_slider_value_changed(value: float) -> void:
	scale_label.text = "%d %%" % int(value)
	GraphicsSettings.set_render_scale(value / 100.0)


func _on_fps_check_toggled(on: bool) -> void:
	GraphicsSettings.set_show_fps(on)


func _on_fullscreen_check_toggled(on: bool) -> void:
	GraphicsSettings.set_fullscreen(on)


func _on_back_button_pressed() -> void:
	close()


func _on_language_button_item_selected(index: int) -> void:
	Preferences.set_language(Preferences.LANGUAGES.keys()[index])
	_refresh()


func _on_controls_button_pressed() -> void:
	$Panel.visible = false
	controls_menu.open()


func _on_controls_menu_closed() -> void:
	$Panel.visible = true
	$Panel/VBox/ControlsButton.grab_focus()
