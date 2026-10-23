extends Control
## Main menu. Nodes in scenes/main_menu.tscn.
## "Jugar" asks how to play (ModePanel: single player or local co-op with a gamepad for
## player 2, GameSession) and then opens the 4 save slots (SaveSlots node, load mode).

@onready var menu_panel: Control = $MenuPanel
@onready var controls_panel: Control = $ControlsPanel
@onready var play_button: Button = $MenuPanel/VBox/PlayButton
@onready var back_button: Button = $ControlsPanel/VBox/BackButton
@onready var click_sound: AudioStreamPlayer = $ClickSound
@onready var save_slots: SaveSlots = $SaveSlots
@onready var mode_panel: Control = $ModePanel
@onready var solo_button: Button = $ModePanel/VBox/SoloButton
@onready var coop_button: Button = $ModePanel/VBox/CoopButton
@onready var mode_info: Label = $ModePanel/VBox/Info
@onready var options: GraphicsOptions = $GraphicsOptions


func _ready() -> void:
	get_tree().paused = false
	get_viewport().disable_3d = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	play_button.grab_focus()


func _on_play_button_pressed() -> void:
	click_sound.play()
	menu_panel.visible = false
	mode_panel.visible = true
	_update_mode_info()
	solo_button.grab_focus()


func _update_mode_info() -> void:
	if GameSession.can_play_coop():
		mode_info.text = "Cooperative: Split screen. Player 1 (Luffy): keyboard and mouse. Player 2 (Zoro): controller."
	else:
		mode_info.text = "For cooperative mode, connect a controller: Player 2 (Zoro) plays whit it."


func _on_solo_button_pressed() -> void:
	click_sound.play()
	GameSession.start(false)
	mode_panel.visible = false
	save_slots.open(SaveSlots.Mode.LOAD)


func _on_coop_button_pressed() -> void:
	click_sound.play()
	if not GameSession.can_play_coop():
		_update_mode_info()
		return
	GameSession.start(true)
	mode_panel.visible = false
	save_slots.open(SaveSlots.Mode.LOAD)


func _on_mode_back_button_pressed() -> void:
	click_sound.play()
	mode_panel.visible = false
	menu_panel.visible = true
	play_button.grab_focus()


func _on_options_button_pressed() -> void:
	click_sound.play()
	menu_panel.visible = false
	options.open()


func _on_graphics_options_closed() -> void:
	click_sound.play()
	menu_panel.visible = true
	play_button.grab_focus()


func _on_save_slots_closed() -> void:
	click_sound.play()
	mode_panel.visible = true
	solo_button.grab_focus()


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
