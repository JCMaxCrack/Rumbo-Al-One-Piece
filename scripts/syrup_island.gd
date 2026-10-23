extends IslandWorld
## Second island, Villa Syrup (scenes/islands/villa_syrup.tscn). See IslandWorld for the shared part.
## The Going Merry arrives at the port of the south. Usopp, on the hill over the village, tells
## Luffy that the butler of the mansion is in fact Captain Kuro, who wants to attack the village.
## Mission:
##   1. take the key of the mansion from the old graveyard of the east (full of skeletons);
##   2. open the gate of the mansion's wall with it (interact at the gate);
##   3. defeat Captain Kuro, who patrols the halls of the mansion (if he sees Luffy he chases him);
##   4. talk to Usopp again: he joins the crew.
## Skeletons and evil mushrooms guard the graveyard, the forest and the mansion.

@onready var usopp: Player = $Usopp
@onready var gate: Node3D = $Mansion/Gate

var _gate_tween: Tween


func _island_ready() -> void:
	boss = $Kuro
	recruit_member = "usopp"
	usopp.control = Player.Controller.NONE


func _apply_island_extra(_st: Dictionary) -> void:
	if gate_open():
		_set_gate_open(false)


func _arrival_message(loaded: bool) -> void:
	if loaded:
		super(loaded)
	else:
		hud.show_banner(tr("Villa Syrup"), tr("Busca a Usopp en la colina sobre la aldea"), 3.0)


func gate_open() -> bool:
	return flags.has("gate_open")


func _interactables() -> Array:
	var out := super()
	if not recruited:
		out.append([usopp, 3.4, "Hablar", _talk_to_usopp])
	if not gate_open():
		out.append([gate, 4.0, "Abrir la reja", _try_gate])
	return out


func _process(delta: float) -> void:
	super(delta)
	var label := usopp.get_node_or_null("PromptLabel") as Label3D
	if label:
		label.visible = not recruited and not hud.is_dialog_open() and usopp.global_position.distance_to(player.global_position) < 3.4


# ------------------------------------------------------------------ Usopp and the mission
func _talk_to_usopp() -> void:
	if mission == Mission.NOT_GIVEN:
		open_dialog("Usopp", [
			"¡Alto ahí! ¡Soy el gran capitán Usopp, con 8000 hombres a mis órdenes!",
			"...Bueno, no. Pero escucha: Klahadore, el mayordomo de la mansión de la colina, ¡es en realidad el Capitán Kuro!",
			"Él y su banda planean atacar la aldea. Nadie me cree porque siempre digo mentiras...",
			"La reja de la mansión está cerrada con llave. La llave está en el viejo cementerio del este, lleno de esqueletos.",
			"¡Si derrotas a Kuro, el gran Usopp se unirá a tu tripulación!",
		], _on_mission_given)
	elif boss.is_defeated():
		open_dialog("Usopp", [
			"¡Lo lograste! ¡Kuro está derrotado y la aldea está a salvo!",
			"Siempre quise ser un valiente guerrero del mar... ¡Capitán Luffy, el gran Usopp se une a tu tripulación!",
		], _recruit_usopp)
	else:
		open_dialog("Usopp", [_progress_line()])


func _on_mission_given() -> void:
	mission = Mission.ACTIVE
	hud.show_message(tr("¡Nueva misión!"), 1.5)
	_update_mission_text()
	_update_boss_hud()


func _recruit_usopp() -> void:
	if recruited:
		return
	recruited = true
	GameState.add_crew("usopp")
	GameState.add_xp(30)
	_update_crew()
	hud.show_message(tr("¡Usopp se unió a la tripulación!"), 2.0)
	_update_mission_text()
	check_mission()


func _progress_line() -> String:
	if not collected_items.has("KeyChest"):
		return tr("La llave está en el viejo cementerio del este. ¡Cuidado con los esqueletos!")
	if not gate_open():
		return tr("¡Tienes la llave! Úsala en la reja de la mansión, en lo alto de la colina.")
	return tr("Kuro está dentro de la mansión. Dicen que se mueve sin hacer ruido... ¡ten cuidado!")


func _try_gate() -> void:
	if GameState.count_of("key") <= 0:
		open_dialog(tr("Reja de la mansión"), ["La reja está cerrada con llave."])
		return
	GameState.remove_item("key")
	flags.append("gate_open")
	_set_gate_open(true)
	hud.show_message(tr("¡La reja de la mansión está abierta!"), 2.0)
	_update_mission_text()
	if SaveManager.current_slot > 0:
		save_game(SaveManager.current_slot)


func _set_gate_open(animate: bool) -> void:
	var left := gate.get_node("Left") as Node3D
	var right := gate.get_node("Right") as Node3D
	for body in gate.find_children("*", "CollisionShape3D", true, false):
		(body as CollisionShape3D).set_deferred("disabled", true)
	if _gate_tween:
		_gate_tween.kill()
	if animate:
		_gate_tween = create_tween().set_parallel(true)
		_gate_tween.tween_property(left, "rotation:y", deg_to_rad(-100), 1.2)
		_gate_tween.tween_property(right, "rotation:y", deg_to_rad(100), 1.2)
	else:
		left.rotation.y = deg_to_rad(-100)
		right.rotation.y = deg_to_rad(100)


func _mission_text() -> String:
	if mission == Mission.NOT_GIVEN:
		return tr("Busca a Usopp en la colina sobre la aldea")
	if mission == Mission.DONE:
		return tr("¡Isla completada!") + "\n" + tr("Zarpa en el Going Merry hacia Whisky Peak")
	var m := func(done: bool) -> String: return "[X]" if done else "[  ]"
	return "%s %s\n%s %s\n%s %s\n%s %s" % [
		m.call(collected_items.has("KeyChest")), tr("Encuentra la llave en el cementerio"),
		m.call(gate_open()), tr("Abre la reja de la mansión"),
		m.call(boss.is_defeated()), tr("Derrota al Capitán Kuro"),
		m.call(recruited), tr("Habla con Usopp")]


func _mission_goals_done() -> bool:
	return boss.is_defeated() and recruited


func _on_item_taken(item: Collectible) -> void:
	if item.item_id == "key":
		hud.show_message(tr("¡La llave de la mansión! Úsala en la reja de la colina"), 2.5)


func _on_boss_down() -> void:
	hud.show_message(tr("¡Derrotaste al Capitán Kuro! Vuelve con Usopp"), 2.5)
