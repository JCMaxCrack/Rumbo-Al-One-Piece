extends IslandWorld
## Second island, Villa Syrup (scenes/islands/villa_syrup.tscn). See IslandWorld for the shared part.
## The Going Merry docks at the port of the south, where Koby waits for Luffy. Koby gives the
## mission: Usopp, a boy of the village, says that Klahadore, the butler of the mansion on the
## north plateau, is in fact Captain Kuro, who wants to attack the village. Nobody believes him.
##   1. take the key of the mansion from the crypt of the old graveyard of the east (skeletons!);
##   2. open the gate of the mansion's wall with it (interact at the gate);
##   3. defeat Captain Kuro, who patrols the halls inside the mansion (if he sees Luffy he chases him);
##   4. talk to Usopp, on the hill over the village: he joins the crew.
## Skeletons and evil mushrooms guard the graveyard, the forest and the roads.

@onready var gate: Node3D = $Mansion/Gate

var usopp: Player
var _gate_tween: Tween


func _island_ready() -> void:
	boss = $Kuro
	recruit_member = "usopp"
	music = load("res://assets/audio/music_villa_syrup.wav")
	usopp = recruit_node()
	if usopp:
		usopp.control = Player.Controller.NONE


func _apply_island_extra(_st: Dictionary) -> void:
	if gate_open():
		_set_gate_open(false)


func arrival_message(loaded: bool) -> void:
	if loaded:
		super(loaded)
	elif mission == Mission.NOT_GIVEN:
		hud.show_banner(tr("Villa Syrup"), tr("Koby te espera en el puerto"), 3.0)
	else:
		hud.show_message(tr("Villa Syrup"), 2.0)


func gate_open() -> bool:
	return flags.has("gate_open")


func _interactables() -> Array:
	var out := super()
	if _usopp_here():
		out.append([usopp, 3.4, "Hablar", _talk_to_usopp])
	if not gate_open():
		out.append([gate, 4.5, "Abrir la reja", _try_gate])
	return out


func _usopp_here() -> bool:
	return is_instance_valid(usopp) and usopp.get_parent() == self and not recruited


func _process(_delta: float) -> void:
	if _usopp_here():
		var label := usopp.get_node_or_null("PromptLabel") as Label3D
		if label:
			label.visible = not hud.is_dialog_open() and usopp.global_position.distance_to(player.global_position) < 3.4


# ------------------------------------------------------------------ Koby, Usopp and the mission
func _talk_to_koby() -> void:
	match mission:
		Mission.NOT_GIVEN:
			open_dialog("Koby", [
				"¡Luffy-san! Llegué antes que tú en un barco de la Marina. Escucha, esta aldea está en peligro.",
				"Un chico de aquí, Usopp, dice que Klahadore, el mayordomo de la mansión del norte, es en realidad el Capitán Kuro.",
				"Nadie le cree porque siempre dice mentiras... pero yo creo que esta vez dice la verdad.",
				"La reja de la mansión está cerrada con llave. La llave está en la cripta del viejo cementerio del este, lleno de esqueletos.",
				"Tu misión: consigue la llave, entra en la mansión y derrota a Kuro. Dicen que recorre sus pasillos sin hacer ruido.",
				"Usopp vive en la colina del oeste, sobre la aldea. ¡Seguro que querrá ir contigo cuando Kuro caiga!",
			], give_mission)
		Mission.ACTIVE:
			open_dialog("Koby", [_progress_line()])
		_:
			open_dialog("Koby", ["¡La aldea está a salvo gracias a ti, Luffy-san!", "La siguiente isla es Whisky Peak. Toma el timón del Going Merry: ¡te veré allí!"])


func _talk_to_usopp() -> void:
	if mission == Mission.NOT_GIVEN:
		open_dialog("Usopp", [
			"¡Alto ahí! ¡Soy el gran capitán Usopp, con 8000 hombres a mis órdenes!",
			"...Bueno, no. Pero tienes que creerme: ¡el mayordomo de la mansión es el Capitán Kuro! Habla con ese chico de la Marina del puerto.",
		])
	elif boss.is_defeated():
		open_dialog("Usopp", [
			"¡Lo lograste! ¡Kuro está derrotado y la aldea está a salvo!",
			"Siempre quise ser un valiente guerrero del mar... ¡Capitán Luffy, el gran Usopp se une a tu tripulación!",
		], recruit)
	else:
		open_dialog("Usopp", ["¡Kuro sigue en la mansión! Yo... yo vigilo la aldea desde aquí. ¡Ten cuidado!"])


func _progress_line() -> String:
	if not collected_items.has("KeyChest"):
		return tr("La llave está en la cripta del viejo cementerio del este. ¡Cuidado con los esqueletos!")
	if not gate_open():
		return tr("¡Tienes la llave! Úsala en la reja de la mansión, en la meseta del norte.")
	if not boss.is_defeated():
		return tr("Kuro está dentro de la mansión. Recorre los salones y los pasillos... ¡ten cuidado!")
	return tr("¡Kuro cayó! Usopp te espera en la colina del oeste.")


func _try_gate() -> void:
	if not GameState.party_take("key", 1):
		open_dialog(tr("Reja de la mansión"), ["La reja está cerrada con llave."])
		return
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
		return tr("Habla con Koby en el puerto")
	if mission == Mission.DONE:
		return tr("¡Isla completada!") + "\n" + tr("Toma el timón del Going Merry y navega hasta Whisky Peak")
	var m := func(done: bool) -> String: return "[X]" if done else "[  ]"
	var text := "%s %s\n%s %s\n%s %s" % [
		m.call(collected_items.has("KeyChest")), tr("Encuentra la llave en el cementerio"),
		m.call(gate_open()), tr("Abre la reja de la mansión"),
		m.call(boss.is_defeated()), tr("Derrota al Capitán Kuro en la mansión")]
	if not GameSession.is_played("usopp"):
		text += "\n%s %s" % [m.call(recruited), tr("Recluta a Usopp en la colina")]
	return text


func _mission_goals_done() -> bool:
	return boss.is_defeated() and recruited


func _on_item_taken(item: Collectible) -> void:
	if item.item_id == "key":
		hud.show_message(tr("¡La llave de la mansión! Úsala en la reja de la meseta del norte"), 2.5)


func _on_boss_down() -> void:
	hud.show_message(tr("¡Derrotaste al Capitán Kuro! Ve a buscar a Usopp a la colina"), 2.5)
