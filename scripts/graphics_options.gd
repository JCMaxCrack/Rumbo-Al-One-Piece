class_name GraphicsOptions
extends Control
## "Opciones" panel (scenes/ui/graphics_options.tscn), used from the main menu and the pause menu.
## Quality preset (Bajo / Medio / Alto), render resolution slider and FPS counter.
## Every change is applied at once and saved by GraphicsSettings.

signal closed

const RENDERER_NAMES := {"forward_plus": "Forward+", "mobile": "Mobile", "gl_compatibility": "Compatibilidad (OpenGL)"}

@onready var preset_button: OptionButton = $Panel/VBox/PresetRow/PresetButton
@onready var scale_slider: HSlider = $Panel/VBox/ScaleRow/ScaleSlider
@onready var scale_label: Label = $Panel/VBox/ScaleRow/ScaleValue
@onready var fps_check: CheckBox = $Panel/VBox/FpsCheck
@onready var info_label: Label = $Panel/VBox/Info
@onready var back_button: Button = $Panel/VBox/BackButton


func open() -> void:
	visible = true
	_refresh()
	preset_button.grab_focus()


func close() -> void:
	visible = false
	closed.emit()


func _refresh() -> void:
	preset_button.select(GraphicsSettings.preset)
	scale_slider.set_value_no_signal(roundf(GraphicsSettings.render_scale * 100.0))
	scale_label.text = "%d %%" % int(scale_slider.value)
	fps_check.set_pressed_no_signal(GraphicsSettings.show_fps)
	var r := GraphicsSettings.renderer()
	info_label.text = "%s\nRenderer: %s" % [GraphicsSettings.settings().description, RENDERER_NAMES.get(r, r)]


func _on_preset_button_item_selected(index: int) -> void:
	GraphicsSettings.set_preset(index)
	_refresh()


func _on_scale_slider_value_changed(value: float) -> void:
	scale_label.text = "%d %%" % int(value)
	GraphicsSettings.set_render_scale(value / 100.0)


func _on_fps_check_toggled(on: bool) -> void:
	GraphicsSettings.set_show_fps(on)


func _on_back_button_pressed() -> void:
	close()
