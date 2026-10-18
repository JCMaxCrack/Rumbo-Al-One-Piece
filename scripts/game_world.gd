extends Node3D
## Main scene logic (scenes/game.tscn).
## Koby gives Luffy the mission: defeat Buggy (in the volcano crater) and collect all the meat.
## Every piece of meat gives back health. Luffy can swim in the sea and board the Going Merry
## from the dock in the north-east inlet. Works with keyboard/mouse, gamepad and touch screen.
## Signals from Luffy, Buggy, Koby, the touch controls and the collectibles are connected in the scene.

enum Mission { NOT_GIVEN, ACTIVE, DONE }

@onready var player: Player = $Luffy
@onready var boss: BuggyBoss = $Buggy
@onready var koby: Koby = $Koby
@onready var collectibles: Node3D = $Collectibles
@onready var hud: HUD = $HUD
@onready var touch_controls: TouchControls = $TouchControls
@onready var pause_menu: PauseMenu = $PauseMenu
@onready var end_screen: EndScreen = $EndScreen
@onready var explore_music: AudioStreamPlayer = $ExploreMusic
@onready var chase_music: AudioStreamPlayer = $ChaseMusic
@onready var victory_sound: AudioStreamPlayer = $VictorySound
@onready var defeat_sound: AudioStreamPlayer = $DefeatSound
@onready var defeat_timer: Timer = $DefeatTimer

var total_items := 0
var collected_items := 0
var elapsed := 0.0
var finished := false
var mission: int = Mission.NOT_GIVEN
var _dialog: PackedStringArray = []
var _dialog_line := 0
var _music_tween: Tween


func _ready() -> void:
	get_tree().paused = false
	total_items = collectibles.get_child_count()
	hud.set_count(collected_items, total_items)
	hud.set_health(player.health, player.max_health)
	hud.set_boss_health(boss.health, boss.max_health)
	hud.set_boss_state(BuggyBoss.STATE_TEXT[boss.state])
	hud.set_touch_mode(touch_controls.active)
	hud.hide_dialog()
	koby.set_prompt("Toca «Hablar»" if touch_controls.active else "[E] Hablar")
	_update_mission_text()
	hud.show_message("¡Habla con Koby!", 2.5)


func _process(delta: float) -> void:
	if not finished:
		elapsed += delta
	touch_controls.set_interact_visible(hud.is_dialog_open() or koby.player_near, "Seguir" if hud.is_dialog_open() else "Hablar")
	if DisplayServer.get_name() == "headless" or touch_controls.active:
		return
	var free_mouse := get_tree().paused or finished
	var want := Input.MOUSE_MODE_VISIBLE if free_mouse else Input.MOUSE_MODE_CAPTURED
	if Input.mouse_mode != want:
		Input.mouse_mode = want


func _unhandled_input(event: InputEvent) -> void:
	if finished:
		return
	if event.is_action_pressed("pause"):
		pause_menu.toggle()
	elif event.is_action_pressed("toggle_debug"):
		boss.set_debug_visible(not boss.show_debug)
	elif event.is_action_pressed("interact"):
		if hud.is_dialog_open():
			_next_dialog_line()
		elif koby.player_near:
			_talk_to_koby()


# ------------------------------------------------------------------ Koby and the mission
func _talk_to_koby() -> void:
	match mission:
		Mission.NOT_GIVEN:
			_dialog = koby.mission_lines
		Mission.ACTIVE:
			_dialog = [_progress_line()]
		_:
			_dialog = ["¡Lo lograste, Luffy-san! ¡Eres increíble!"]
	_dialog_line = 0
	player.controls_enabled = false
	hud.show_dialog("Koby", _dialog[0], _dialog.size() == 1)


func _next_dialog_line() -> void:
	_dialog_line += 1
	if _dialog_line < _dialog.size():
		hud.show_dialog("Koby", _dialog[_dialog_line], _dialog_line == _dialog.size() - 1)
		return
	hud.hide_dialog()
	player.controls_enabled = true
	if mission == Mission.NOT_GIVEN:
		mission = Mission.ACTIVE
		koby.set_mission_given(true)
		hud.show_message("¡Nueva misión!", 1.5)
		_update_mission_text()
		_check_mission()


func _progress_line() -> String:
	var missing := []
	if not boss.is_defeated():
		missing.append("derrotar a Buggy en el cráter")
	if collected_items < total_items:
		missing.append("recolectar %d carne(s) más" % (total_items - collected_items))
	return "¡Ánimo, Luffy-san! Todavía te falta " + " y ".join(missing) + "."


func _update_mission_text() -> void:
	if mission == Mission.NOT_GIVEN:
		hud.set_mission("Habla con Koby en la playa del sur")
		return
	var boss_mark := "[X]" if boss.is_defeated() else "[  ]"
	var meat_mark := "[X]" if collected_items >= total_items else "[  ]"
	hud.set_mission("%s Derrota a Buggy el Payaso\n%s Recolecta la carne (%d/%d)" % [boss_mark, meat_mark, collected_items, total_items])


func _check_mission() -> void:
	if mission == Mission.ACTIVE and boss.is_defeated() and collected_items >= total_items:
		mission = Mission.DONE
		_finish(true)


# ------------------------------------------------------------------ signals (connected in the scene)
func _on_item_collected(item: Collectible) -> void:
	if not is_node_ready():
		return
	collected_items += 1
	hud.set_count(collected_items, total_items)
	_update_mission_text()
	if mission == Mission.ACTIVE and collected_items >= total_items and boss.is_defeated():
		_check_mission()
	else:
		hud.show_message("¡Carne! +%d de vida  (%d/%d)" % [int(item.heal_amount), collected_items, total_items], 1.2)


func _on_buggy_state_changed(new_state: int) -> void:
	if not is_node_ready():
		return
	hud.set_boss_state(BuggyBoss.STATE_TEXT[new_state])
	if finished or new_state == BuggyBoss.State.DEFEATED:
		return
	if new_state == BuggyBoss.State.CHASE:
		hud.show_message("¡Buggy te vio!", 1.0)
		_crossfade(chase_music, explore_music)
	elif new_state == BuggyBoss.State.RETURN:
		hud.show_message("¡Escapaste!", 1.0)
		_crossfade(explore_music, chase_music)


func _on_buggy_defeated() -> void:
	if not is_node_ready():
		return
	_crossfade(explore_music, chase_music)
	_update_mission_text()
	if mission == Mission.ACTIVE and collected_items >= total_items:
		_check_mission()
	else:
		hud.show_message("¡Derrotaste a Buggy el Payaso!", 2.0)


func _on_player_died() -> void:
	if not is_node_ready():
		return
	if finished:
		return
	hud.show_message("¡Buggy te derrotó!", 1.5)
	defeat_timer.start()


func _on_defeat_timer_timeout() -> void:
	_finish(false)


func _finish(won: bool) -> void:
	finished = true
	player.controls_enabled = false
	touch_controls.game_running = false
	hud.hide_dialog()
	explore_music.stop()
	chase_music.stop()
	if won:
		victory_sound.play()
	else:
		defeat_sound.play()
	end_screen.show_result(won, elapsed, collected_items, total_items, boss.is_defeated())
	get_tree().paused = true


func _crossfade(to_player: AudioStreamPlayer, from_player: AudioStreamPlayer) -> void:
	if _music_tween:
		_music_tween.kill()
	if not to_player.playing:
		to_player.volume_db = -40.0
		to_player.play()
	_music_tween = create_tween().set_parallel(true)
	_music_tween.tween_property(to_player, "volume_db", -8.0, 1.0)
	_music_tween.tween_property(from_player, "volume_db", -40.0, 1.0)
	_music_tween.chain().tween_callback(from_player.stop)
