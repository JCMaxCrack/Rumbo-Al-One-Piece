class_name EndScreen
extends CanvasLayer
## Victory / defeat screen. Nodes in scenes/ui/end_screen.tscn.

@onready var title_label: Label = $Panel/VBox/Title
@onready var detail_label: Label = $Panel/VBox/Detail
@onready var retry_button: Button = $Panel/VBox/RetryButton


func show_result(won: bool, time_seconds: float, collected: int, total: int, boss_defeated: bool) -> void:
	visible = true
	var t := int(time_seconds)
	if won:
		title_label.text = "¡Misión cumplida!"
		title_label.modulate = Color(1, 0.85, 0.4)
		detail_label.text = "Derrotaste a Buggy el Payaso y recolectaste toda la carne (%d/%d).\nTiempo: %d:%02d" % [collected, total, t / 60, t % 60]
	else:
		title_label.text = "¡Buggy te derrotó!"
		title_label.modulate = Color(1, 0.45, 0.4)
		detail_label.text = "Buggy: %s  ·  Carne recogida: %d/%d\nTiempo: %d:%02d" % ["derrotado" if boss_defeated else "sigue en pie", collected, total, t / 60, t % 60]
	retry_button.grab_focus()


func _on_retry_button_pressed() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func _on_menu_button_pressed() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
