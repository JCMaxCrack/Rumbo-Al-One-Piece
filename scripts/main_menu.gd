extends Control
## Main menu. Nodes in scenes/main_menu.tscn.
## "Jugar" opens the 4 save slots (SaveSlots node, load mode).

@onready var menu_panel: Control = $MenuPanel
@onready var controls_panel: Control = $ControlsPanel
@onready var play_button: Button = $MenuPanel/VBox/PlayButton
@onready var back_button: Button = $ControlsPanel/VBox/BackButton
@onready var click_sound: AudioStreamPlayer = $ClickSound
@onready var save_slots: SaveSlots = $SaveSlots


func _ready() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	play_button.grab_focus()


func _on_play_button_pressed() -> void:
	click_sound.play()
	menu_panel.visible = false
	save_slots.open(SaveSlots.Mode.LOAD)


func _on_save_slots_closed() -> void:
	click_sound.play()
	menu_panel.visible = true
	play_button.grab_focus()


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
