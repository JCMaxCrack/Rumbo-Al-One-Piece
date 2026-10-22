class_name HUD
extends CanvasLayer
## In-game interface. Nodes in scenes/ui/hud.tscn.

const KEYBOARD_HINT := "WASD mover  ·  Shift correr  ·  Espacio saltar/nadar  ·  Clic/J golpe  ·  E hablar  ·  M mapa  ·  Mouse cámara  ·  Esc pausa"
const TOUCH_HINT := "Joystick: mover (al borde corre)  ·  Arrastra a la derecha: cámara"

@onready var health_bar: ProgressBar = $Root/PlayerPanel/VBox/HealthBar
@onready var health_label: Label = $Root/PlayerPanel/VBox/Row/HealthLabel
@onready var item_label: Label = $Root/ItemPanel/ItemLabel
@onready var mission_label: Label = $Root/MissionPanel/VBox/MissionText
@onready var boss_health_bar: ProgressBar = $Root/BossBox/BossHealthBar
@onready var boss_health_label: Label = $Root/BossBox/BossHealthBar/BossHealthLabel
@onready var boss_state_label: Label = $Root/BossBox/BossState
@onready var message_label: Label = $Root/Message
@onready var message_timer: Timer = $MessageTimer
@onready var dialog_panel: Control = $Root/DialogPanel
@onready var dialog_speaker: Label = $Root/DialogPanel/VBox/Speaker
@onready var dialog_text: Label = $Root/DialogPanel/VBox/Text
@onready var dialog_hint: Label = $Root/DialogPanel/VBox/Hint
@onready var controls_hint: Label = $Root/ControlsHint
@onready var fps_label: Label = $Root/FpsLabel
@onready var minimap: Minimap = $Root/Minimap
@onready var player2_panel: Control = $Root/Player2Panel
@onready var health_bar2: ProgressBar = $Root/Player2Panel/VBox/HealthBar
@onready var health_label2: Label = $Root/Player2Panel/VBox/Row/HealthLabel

var touch_mode := false


func set_health(current: float, maximum: float) -> void:
	health_bar.max_value = maximum
	health_bar.value = current
	health_label.text = "%d / %d" % [int(ceil(current)), int(maximum)]


## Health of Zoro (player 2 in co-op, or the companion once he joins the crew).
func set_health2(current: float, maximum: float) -> void:
	health_bar2.max_value = maximum
	health_bar2.value = current
	health_label2.text = "%d / %d" % [int(ceil(current)), int(maximum)]


func set_player2_visible(on: bool) -> void:
	player2_panel.visible = on


## M / D-pad up: small map around the player <-> the whole island.
func toggle_map() -> void:
	minimap.toggle_big()


func set_count(current: int, total: int) -> void:
	item_label.text = "Carne: %d / %d" % [current, total]


func set_mission(text: String) -> void:
	mission_label.text = text


func set_boss_health(current: float, maximum: float) -> void:
	boss_health_bar.max_value = maximum
	boss_health_bar.value = current
	boss_health_label.text = "%d / %d" % [int(ceil(current)), int(maximum)]


## Buggy's name, health and AI state (hidden until Koby gives the mission and after Buggy falls).
func set_boss_visible(on: bool) -> void:
	$Root/BossBox.visible = on


func set_boss_state(text: String) -> void:
	boss_state_label.text = "IA: " + text


func set_touch_mode(on: bool) -> void:
	touch_mode = on
	controls_hint.text = TOUCH_HINT if on else KEYBOARD_HINT


func show_message(text: String, duration: float = 2.0) -> void:
	message_label.text = text
	message_label.visible = true
	message_timer.start(duration)


func show_dialog(speaker: String, text: String, last: bool) -> void:
	dialog_panel.visible = true
	dialog_speaker.text = speaker
	dialog_text.text = text
	var key := "Toca «Seguir»" if touch_mode else "Pulsa E"
	dialog_hint.text = key + (" para cerrar" if last else " para continuar")


func hide_dialog() -> void:
	dialog_panel.visible = false


func is_dialog_open() -> bool:
	return dialog_panel.visible


## FPS counter (Opciones -> Mostrar FPS).
func _process(_delta: float) -> void:
	fps_label.visible = GraphicsSettings.show_fps
	if fps_label.visible:
		fps_label.text = "%d FPS" % Engine.get_frames_per_second()


func _on_message_timer_timeout() -> void:
	message_label.visible = false
