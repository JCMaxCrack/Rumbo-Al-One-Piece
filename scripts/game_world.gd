extends IslandWorld
## First island, "Isla del Payaso" (scenes/game.tscn). See IslandWorld for what all the islands share.
## Koby gives Luffy the mission: defeat Buggy (in the volcano crater), collect all the meat of the
## island and, in single player, recruit Zoro: he is tied to a post in the north-west forest and
## joins the crew if Luffy gives him 3 pieces of meat from the inventory. In local co-op Zoro is
## player 2 from the start. Luffy can swim and board the Going Merry from the dock in the
## north-east inlet; when the mission is done its helm sails to Villa Syrup.
## Signals of Luffy, Buggy, the checkpoints and the meat are connected in the scene.

const MEAT_FOR_ZORO := 3
const KOBY_ZORO_LINE := "Una cosa más: en el bosque del noroeste los marines tienen atado a un espadachín, Roronoa Zoro. ¡Recluta a Zoro para tu tripulación!"
const KOBY_COOP_LINE := "¡Y qué suerte que Zoro, el espadachín, ya viaja contigo!"

@onready var koby: Koby = $Koby

var zoro: Player
var zoro_recruited: bool:
	get:
		return recruited
	set(v):
		recruited = v


func _island_ready() -> void:
	boss = $Buggy
	zoro = $Zoro
	connect_boss_signals = false
	recruit_member = "zoro"
	koby.set_prompt(tr("Toca «Hablar»") if touch_controls.active else tr("[E] Hablar"))
	hud.set_boss_name(tr("Buggy el Payaso"))
	hud.set_boss_health(boss.health, boss.max_health)
	hud.set_boss_state(tr(BuggyBoss.STATE_TEXT[boss.state]))
	if GameSession.coop:
		recruited = true


func _arrival_message(loaded: bool) -> void:
	if loaded:
		super(loaded)
	elif mission == Mission.NOT_GIVEN:
		hud.show_message(tr("¡Habla con Koby!"), 2.5)


func _apply_island_extra(_st: Dictionary) -> void:
	koby.set_mission_given(mission >= Mission.ACTIVE)
	if GameSession.coop:
		recruited = true
	hud.set_boss_state(tr(BuggyBoss.STATE_TEXT[boss.state]))


func _interactables() -> Array:
	var out := super()
	if koby.player_near:
		out.append([koby, 99.0, "Hablar", _talk_to_koby])
	if _zoro_near():
		out.append([zoro, 3.2, "Hablar", _talk_to_zoro])
	return out


func _zoro_near() -> bool:
	return not GameSession.coop and not recruited and zoro.global_position.distance_to(player.global_position) < 3.2


func _process(delta: float) -> void:
	super(delta)
	zoro.get_node("NameLabel").visible = not GameSession.coop and not recruited
	zoro.get_node("PromptLabel").visible = _zoro_near() and not hud.is_dialog_open()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_debug") and not finished:
		boss.set_debug_visible(not boss.show_debug)
		return
	super(event)


# ------------------------------------------------------------------ Koby and the mission
func _talk_to_koby() -> void:
	var lines: Array = []
	match mission:
		Mission.NOT_GIVEN:
			lines = Array(koby.mission_lines)
			lines.append(KOBY_COOP_LINE if GameSession.coop else KOBY_ZORO_LINE)
		Mission.ACTIVE:
			lines = [_progress_line()]
		_:
			lines = ["¡Lo lograste, Luffy-san! ¡Eres increíble!", "El Going Merry te espera en el muelle: usa el timón para zarpar hacia Villa Syrup."]
	open_dialog("Koby", lines, _on_koby_done)


func _on_koby_done() -> void:
	if mission == Mission.NOT_GIVEN:
		mission = Mission.ACTIVE
		koby.set_mission_given(true)
		hud.show_message(tr("¡Nueva misión!"), 1.5)
		_update_mission_text()
		_update_boss_hud()
		check_mission()


## Zoro, tied up: he joins the crew when Luffy gives him some meat.
func _talk_to_zoro() -> void:
	if GameState.count_of("meat") >= MEAT_FOR_ZORO:
		open_dialog("Zoro", ["¡Por fin comida! ...Está bien, me uniré a tu tripulación.", "Pero escucha: mi sueño es ser el mejor espadachín del mundo. ¡Que no se te olvide, capitán!"], _recruit_zoro)
	else:
		open_dialog("Zoro", ["¿Y tú quién eres? Soy Roronoa Zoro. Los marines me ataron aquí y llevo días sin comer...",
			tr("Si me traes %d carnes, me uniré a tu tripulación. (Tienes %d)") % [MEAT_FOR_ZORO, GameState.count_of("meat")]])


func _recruit_zoro() -> void:
	if recruited or GameState.count_of("meat") < MEAT_FOR_ZORO:
		return
	GameState.remove_item("meat", MEAT_FOR_ZORO)
	recruited = true
	GameState.add_crew("zoro")
	GameState.add_xp(30)
	_update_crew()
	hud.show_message(tr("¡Zoro se unió a la tripulación!"), 2.0)
	_update_mission_text()
	check_mission()


func _progress_line() -> String:
	var missing := []
	if not boss.is_defeated():
		missing.append(tr("derrotar a Buggy en el cráter"))
	if _meat_taken() < _meat_total():
		missing.append(tr("recolectar %d carne(s) más") % (_meat_total() - _meat_taken()))
	if not recruited:
		missing.append(tr("reclutar a Zoro en el bosque del noroeste"))
	return tr("¡Ánimo, Luffy-san! Todavía te falta ") + tr(" y ").join(missing) + "."


func _mission_text() -> String:
	if mission == Mission.NOT_GIVEN:
		return tr("Habla con Koby en la playa del sur")
	if mission == Mission.DONE:
		return tr("¡Isla completada!") + "\n" + tr("Zarpa en el Going Merry hacia Villa Syrup")
	var boss_mark := "[X]" if boss.is_defeated() else "[  ]"
	var meat_mark := "[X]" if _meat_taken() >= _meat_total() else "[  ]"
	var zoro_mark := "[X]" if recruited else "[  ]"
	var text := "%s %s\n%s %s" % [boss_mark, tr("Derrota a Buggy el Payaso"), meat_mark, tr("Recolecta la carne (%d/%d)") % [_meat_taken(), _meat_total()]]
	if not GameSession.coop:
		text += "\n%s %s" % [zoro_mark, tr("Recluta a Zoro")]
	return text


func _mission_goals_done() -> bool:
	return boss.is_defeated() and _meat_taken() >= _meat_total() and recruited


# ------------------------------------------------------------------ signals of the scene
func _on_buggy_state_changed(new_state: int) -> void:
	if not is_node_ready():
		return
	hud.set_boss_state(tr(BuggyBoss.STATE_TEXT[new_state]))
	if finished or new_state == BuggyBoss.State.DEFEATED:
		return
	if new_state == BuggyBoss.State.CHASE:
		hud.show_message(tr("¡Buggy te vio!"), 1.0)
		_crossfade(chase_music, explore_music)
	elif new_state == BuggyBoss.State.RETURN:
		hud.show_message(tr("¡Escapaste!"), 1.0)
		_crossfade(explore_music, chase_music)


func _on_buggy_defeated() -> void:
	if not is_node_ready():
		return
	_crossfade(explore_music, chase_music)
	_update_mission_text()
	# the bar shows Buggy's empty health for a moment and then goes away
	get_tree().create_timer(1.5).timeout.connect(_update_boss_hud)
	hud.show_message(tr("¡Derrotaste a Buggy el Payaso!"), 2.0)
	check_mission()


## Buggy's health bar: only while the mission is active and Buggy is still standing.
func _update_boss_hud() -> void:
	if is_inside_tree():
		hud.set_boss_visible(mission == Mission.ACTIVE and not boss.is_defeated())


## Zoro is revived by IslandWorld._on_crew_died (this old connection of the scene does nothing).
func _on_zoro_died() -> void:
	pass
