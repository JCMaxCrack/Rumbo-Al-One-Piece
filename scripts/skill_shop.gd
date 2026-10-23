class_name SkillShop
extends CanvasLayer
## Skill shop (scenes/ui/skill_shop.tscn), opened with K / D-pad down. Every level up gives one
## skill point; here Luffy learns new attacks with them and chooses the one he uses (R / RB).
## Only the skills of the islands already reached appear (2 per island, GameState.SKILLS).
## The game is paused while it is open.

signal closed

@onready var points_label: Label = $Panel/VBox/Points
@onready var list: VBoxContainer = $Panel/VBox/Scroll/List
@onready var info_label: Label = $Panel/VBox/Info
@onready var close_button: Button = $Panel/VBox/CloseButton
@onready var buy_sound: AudioStreamPlayer = $BuySound


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false


func open() -> void:
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	info_label.text = ""
	_refresh()
	close_button.grab_focus()


func close() -> void:
	visible = false
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("pause") or event.is_action_pressed("shop") or event.is_action_pressed("ui_cancel")):
		get_viewport().set_input_as_handled()
		close()


func _refresh() -> void:
	points_label.text = tr("Nivel %d  ·  Puntos de habilidad: %d") % [GameState.level, GameState.skill_points]
	for c in list.get_children():
		list.remove_child(c)
		c.queue_free()
	var available := GameState.shop_skills()
	for id in GameState.SKILLS:
		var spec: Dictionary = GameState.SKILLS[id]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		var texts := VBoxContainer.new()
		texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var name_label := Label.new()
		name_label.add_theme_font_size_override("font_size", 22)
		var desc := Label.new()
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.add_theme_font_size_override("font_size", 15)
		desc.modulate = Color(0.85, 0.85, 0.85)
		texts.add_child(name_label)
		texts.add_child(desc)
		row.add_child(texts)
		var button := Button.new()
		button.custom_minimum_size = Vector2(170, 44)
		row.add_child(button)
		var owned := GameState.skills.has(id)
		if available.has(id):
			name_label.text = "%s  (%s)" % [tr(spec.name), tr("%d punto(s)") % int(spec.cost)]
			desc.text = tr(spec.text) + "  " + tr("Daño %d · espera %d s") % [int(spec.damage), int(spec.cooldown)]
			if owned:
				button.text = tr("Equipada") if GameState.equipped == id else tr("Equipar")
				button.disabled = GameState.equipped == id
				button.pressed.connect(_on_equip.bind(id))
			else:
				button.text = tr("Aprender")
				button.disabled = not GameState.can_learn(id)
				button.pressed.connect(_on_learn.bind(id))
		else:
			name_label.text = "???"
			desc.text = tr("Se desbloquea al llegar a %s") % tr(GameState.ISLAND_NAMES[GameState.ISLANDS[int(spec.island)]])
			button.text = tr("Bloqueada")
			button.disabled = true
			row.modulate = Color(1, 1, 1, 0.55)
		list.add_child(row)


func _on_learn(id: String) -> void:
	if GameState.learn(id):
		buy_sound.play()
		info_label.text = tr("¡Aprendiste %s!") % tr(GameState.SKILLS[id].name)
	_refresh()


func _on_equip(id: String) -> void:
	GameState.equip(id)
	info_label.text = tr("Habilidad equipada: %s") % tr(GameState.SKILLS[id].name)
	_refresh()


func _on_close_button_pressed() -> void:
	close()
