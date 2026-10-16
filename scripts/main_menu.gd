extends Control
## Main menu. Nodes in scenes/main_menu.tscn.

@onready var menu_panel: Control = $MenuPanel
@onready var controls_panel: Control = $ControlsPanel
@onready var play_button: Button = $MenuPanel/VBox/PlayButton
@onready var back_button: Button = $ControlsPanel/VBox/BackButton
@onready var click_sound: AudioStreamPlayer = $ClickSound


func _ready() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	play_button.grab_focus()


func _on_play_button_pressed() -> void:
	click_sound.play()
	get_tree().change_scene_to_file("res://scenes/game.tscn")


func _on_controls_button_pressed() -> void:
	click_sound.play()
	menu_panel.visible = false
	controls_panel.visible = true
	back_button.grab_focus()


func _on_back_button_pressed() -> void:
	click_sound.play()
	controls_panel.visible = false
	menu_panel.visible = true
	play_button.grab_focus()


func _on_quit_button_pressed() -> void:
	get_tree().quit()
