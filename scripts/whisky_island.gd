extends IslandWorld
## Third island, Whisky Peak (scenes/islands/whisky_peak.tscn). See IslandWorld for the shared part.
## A town at the foot of giant cactus-shaped rocks. Nami, in the town square, tells Luffy that
## Vice Admiral Garp (his grandfather!) arrived to take him to the Navy... by force.
## Mission:
##   1. pick 5 tangerines from the trees among the cactus rocks and give them to Nami;
##   2. defeat Garp, who waits on the plateau of the great cactus;
##   3. Nami joins the crew as navigator. It is the last island of this version: the voyage ends.

const ORANGES_FOR_NAMI := 5

@onready var nami: Player = $Nami

var oranges_given: bool:
	get:
		return flags.has("oranges_given")
	set(v):
		if v and not flags.has("oranges_given"):
			flags.append("oranges_given")


func _island_ready() -> void:
	boss = $Garp
	recruit_member = "nami"
	nami.control = Player.Controller.NONE


func _arrival_message(loaded: bool) -> void:
	if loaded:
		super(loaded)
	else:
		hud.show_banner(tr("Whisky Peak"), tr("Busca a Nami en la plaza del pueblo"), 3.0)


func _interactables() -> Array:
	var out := super()
	if not recruited:
		out.append([nami, 3.4, "Hablar", _talk_to_nami])
	return out


func _process(delta: float) -> void:
	super(delta)
	var label := nami.get_node_or_null("PromptLabel") as Label3D
	if label:
		label.visible = not recruited and not hud.is_dialog_open() and nami.global_position.distance_to(player.global_position) < 3.4


func _talk_to_nami() -> void:
	if mission == Mission.NOT_GIVEN:
		open_dialog("Nami", [
			"Hola, Luffy. Soy Nami, la mejor navegante de East Blue.",
			"Tengo malas noticias: el vicealmirante Garp de la Marina llegó a la isla... ¡dice que es tu abuelo!",
			"Quiere llevarte a la Marina a puñetazos. Te espera en la meseta del gran cactus, al norte del pueblo.",
			tr("Hagamos un trato: tráeme %d mandarinas de los árboles entre los cactus y derrota a Garp.") % ORANGES_FOR_NAMI,
			"Si lo logras, seré la navegante de tu tripulación. ¡Sin mí no llegarán nunca al Grand Line!",
		], _on_mission_given)
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
		], _recruit_nami)
	elif oranges_given:
		open_dialog("Nami", ["¡Gracias por las mandarinas! Ahora derrota a Garp en la meseta del gran cactus."])
	else:
		open_dialog("Nami", [tr("Todavía me faltan mandarinas: tienes %d de %d.") % [GameState.count_of("orange"), ORANGES_FOR_NAMI]])


func _on_mission_given() -> void:
	mission = Mission.ACTIVE
	hud.show_message(tr("¡Nueva misión!"), 1.5)
	_update_mission_text()
	_update_boss_hud()


func _recruit_nami() -> void:
	if recruited:
		return
	recruited = true
	GameState.add_crew("nami")
	GameState.add_xp(30)
	_update_crew()
	hud.show_message(tr("¡Nami se unió a la tripulación!"), 2.0)
	_update_mission_text()
	check_mission()


func _mission_text() -> String:
	if mission == Mission.NOT_GIVEN:
		return tr("Busca a Nami en la plaza del pueblo")
	if mission == Mission.DONE:
		return tr("¡Aventura completada!")
	var m := func(done: bool) -> String: return "[X]" if done else "[  ]"
	var have := mini(GameState.count_of("orange"), ORANGES_FOR_NAMI) if not oranges_given else ORANGES_FOR_NAMI
	return "%s %s\n%s %s\n%s %s" % [
		m.call(oranges_given), tr("Lleva mandarinas a Nami (%d/%d)") % [have, ORANGES_FOR_NAMI],
		m.call(boss.is_defeated()), tr("Derrota al vicealmirante Garp"),
		m.call(recruited), tr("Recluta a Nami")]


func _mission_goals_done() -> bool:
	return boss.is_defeated() and recruited


func _on_item_taken(_item: Collectible) -> void:
	_update_mission_text()


func _on_boss_down() -> void:
	hud.show_message(tr("¡Derrotaste a Garp! Vuelve con Nami"), 2.5)
