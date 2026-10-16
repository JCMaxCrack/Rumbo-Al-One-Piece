class_name HUD
extends CanvasLayer
## In-game interface. Nodes in scenes/ui/hud.tscn.

@onready var health_bar: ProgressBar = $Root/PlayerPanel/VBox/HealthBar
@onready var health_label: Label = $Root/PlayerPanel/VBox/Row/HealthLabel
@onready var item_label: Label = $Root/ItemPanel/ItemLabel
@onready var boss_state_label: Label = $Root/BossBox/BossState
@onready var message_label: Label = $Root/Message
@onready var message_timer: Timer = $MessageTimer


func set_health(current: float, maximum: float) -> void:
	health_bar.max_value = maximum
	health_bar.value = current
	health_label.text = "%d / %d" % [int(ceil(current)), int(maximum)]


func set_count(current: int, total: int) -> void:
	item_label.text = "Carne: %d / %d" % [current, total]


func set_boss_state(text: String) -> void:
	boss_state_label.text = "IA: " + text


func show_message(text: String, duration: float = 2.0) -> void:
	message_label.text = text
	message_label.visible = true
	message_timer.start(duration)


func _on_message_timer_timeout() -> void:
	message_label.visible = false
