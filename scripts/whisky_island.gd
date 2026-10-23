extends IslandWorld
## Third island, Whisky Peak (scenes/islands/whisky_peak.tscn). See IslandWorld for the shared part.
## A town at the foot of giant cactus-shaped rocks. Koby waits at the entrance of the town: Vice
## Admiral Garp (Luffy's grandfather!) arrived to take him to the Navy... by force. And Nami, the
## best navigator of East Blue, is in the town square: she would join a crew that brings her
## tangerines.
##   1. defeat Garp, who waits on the plateau of the great cactus, north of the town;
##   2. pick 5 tangerines from among the cactus rocks and give them to Nami;
##   3. Nami joins the crew as navigator. It is the last island of this version: the voyage ends.

const ORANGES_FOR_NAMI := 5

var nami: Player
var oranges_given: bool:
	get:
		return flags.has("oranges_given")
	set(v):
		if v and not flags.has("oranges_given"):
			flags.append("oranges_given")


func _island_ready() -> void:
	boss = $Garp
	recruit_member = "nami"
	music = load("res://assets/audio/music_whisky_peak.wav")
	nami = recruit_node()
	if nami:
		nami.control = Player.Controller.NONE


func arrival_message(loaded: bool) -> void:
	if loaded:
		super(loaded)
	elif mission == Mission.NOT_GIVEN:
		hud.show_banner(tr("Whisky Peak"), tr("Koby te espera en la entrada del pueblo"), 3.0)
	else:
		hud.show_message(tr("Whisky Peak"), 2.0)


func _interactables() -> Array:
	var out := super()
	if _nami_here():
		out.append([nami, 3.4, "Hablar", _talk_to_nami])
	return out


func _nami_here() -> bool:
	return is_instance_valid(nami) and nami.get_parent() == self and not recruited


func _process(_delta: float) -> void:
	if _nami_here():
		var label := nami.get_node_or_null("PromptLabel") as Label3D
		if label:
			label.visible = not hud.is_dialog_open() and nami.global_position.distance_to(player.global_position) < 3.4


# ------------------------------------------------------------------ Koby, Nami and the mission
func _talk_to_koby() -> void:
	match mission:
		Mission.NOT_GIVEN:
			open_dialog("Koby", [
				"¡Luffy-san, malas noticias! El vicealmirante Garp de la Marina llegó a Whisky Peak... ¡y dice que es tu abuelo!",
				"Quiere llevarte a la Marina a puñetazos. Te espera en la meseta del gran cactus, al norte del pueblo.",
				"Y en la plaza está Nami, la mejor navegante de East Blue. Sin ella nunca llegarán al Grand Line.",
				tr("Dice que solo se unirá a una tripulación que le traiga %d mandarinas de los árboles entre los cactus.") % ORANGES_FOR_NAMI,
				"Tu misión: ¡derrota a Garp, lleva las mandarinas a Nami y recluta a tu navegante!",
			], give_mission)
		Mission.ACTIVE:
			open_dialog("Koby", [_progress_line()])
		_:
			open_dialog("Koby", ["¡Increíble, Luffy-san! Algún día serás el Rey de los Piratas."])


func _talk_to_nami() -> void:
	if mission == Mission.NOT_GIVEN:
		open_dialog("Nami", ["Hola. Soy Nami, la mejor navegante de East Blue.", "¿Un pirata? Hmm... habla primero con ese chico de la Marina de la entrada."])
		return
	if not oranges_given and GameState.count_of("orange") >= ORANGES_FOR_NAMI:
		GameState.remove_item("orange", ORANGES_FOR_NAMI)
		oranges_given = true
		hud.show_message(tr("Le diste %d mandarinas a Nami") % ORANGES_FOR_NAMI, 2.0)
		_update_mission_text()
	if oranges_given and boss.is_defeated():
		open_dialog("Nami", [
			"¡Mis mandarinas! Y además derrotaste al mismísimo Garp...",
			"Está bien, capitán: desde hoy soy la navegante de los Piratas del Sombrero de Paja. ¡Rumbo al Grand Line!",
		], recruit)
	elif oranges_given:
		open_dialog("Nami", ["¡Gracias por las mandarinas! Ahora derrota a Garp en la meseta del gran cactus."])
	else:
		open_dialog("Nami", [tr("Todavía me faltan mandarinas: tienes %d de %d. Crecen entre las rocas de cactus.") % [GameState.count_of("orange"), ORANGES_FOR_NAMI]])


func _progress_line() -> String:
	if not boss.is_defeated():
		return tr("Garp te espera en la meseta del gran cactus, al norte. ¡Lanza balas de cañón desde lejos!")
	if not oranges_given:
		return tr("Busca las mandarinas entre las rocas de cactus y llévaselas a Nami, en la plaza.")
	return tr("¡Nami te espera en la plaza!")


func _mission_text() -> String:
	if mission == Mission.NOT_GIVEN:
		return tr("Habla con Koby en la entrada del pueblo")
	if mission == Mission.DONE:
		return tr("¡Aventura completada!")
	var m := func(done: bool) -> String: return "[X]" if done else "[  ]"
	var have := mini(GameState.count_of("orange"), ORANGES_FOR_NAMI) if not oranges_given else ORANGES_FOR_NAMI
	return "%s %s\n%s %s\n%s %s" % [
		m.call(boss.is_defeated()), tr("Derrota al vicealmirante Garp"),
		m.call(oranges_given), tr("Lleva mandarinas a Nami (%d/%d)") % [have, ORANGES_FOR_NAMI],
		m.call(recruited), tr("Recluta a Nami")]


func _mission_goals_done() -> bool:
	return boss.is_defeated() and recruited


func _on_item_taken(_item: Collectible) -> void:
	_update_mission_text()


func _on_boss_down() -> void:
	hud.show_message(tr("¡Derrotaste a Garp! Lleva las mandarinas a Nami"), 2.5)
