class_name PauseMenu
extends CanvasLayer
## Pause menu. Nodes in scenes/ui/pause_menu.tscn.

@onready var continue_button: Button = $Panel/VBox/ContinueButton


func toggle() -> void:
	visible = not visible
	get_tree().paused = visible
	if visible:
		continue_button.grab_focus()


func _on_continue_button_pressed() -> void:
	toggle()


func _on_menu_button_pressed() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _on_quit_button_pressed() -> void:
	get_tree().quit()
