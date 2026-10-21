extends Node3D
## Main scene logic (scenes/game.tscn).
## Koby gives Luffy the mission: defeat Buggy (in the volcano crater) and collect all the meat.
## Every piece of meat gives back health. Luffy can swim in the sea and board the Going Merry
## from the dock in the north-east inlet. Works with keyboard/mouse, gamepad and touch screen.
## Signals from Luffy, Buggy, Koby, the touch controls, the checkpoints and the collectibles are
## connected in the scene.
## Saving: the progress is saved in the slot chosen in the menu (SaveManager, a JSON file) every
## time Luffy reaches a Checkpoint, from the pause menu ("Guardar partida", in any of the 4 slots)
## and when the mission is done. Loading a slot puts Luffy at the last checkpoint he reached.

enum Mission { NOT_GIVEN, ACTIVE, DONE }

@onready var player: Player = $Luffy
@onready var boss: BuggyBoss = $Buggy
@onready var koby: Koby = $Koby
@onready var collectibles: Node3D = $Collectibles
@onready var checkpoints: Node3D = $Checkpoints
@onready var chunks: ChunkManager = $ChunkManager
@onready var sun: DirectionalLight3D = $Sun
@onready var world_environment: WorldEnvironment = $WorldEnvironment
@onready var terrain_shape: CollisionShape3D = $Island/TerrainBody/CollisionShape3D
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
## Names of the meat nodes already eaten (they are saved).
var collected_meat: Array = []
## Checkpoint where Luffy comes back, and every checkpoint he has reached.
var current_checkpoint: String = SaveManager.FIRST_CHECKPOINT
var activated_checkpoints: Array = [SaveManager.FIRST_CHECKPOINT]
var _dialog: PackedStringArray = []
var _dialog_line := 0
var _music_tween: Tween


func _ready() -> void:
	get_tree().paused = false
	_apply_graphics()
	GraphicsSettings.changed.connect(_apply_graphics)
	total_items = collectibles.get_child_count()
	hud.set_count(collected_items, total_items)
	hud.set_health(player.health, player.max_health)
	hud.set_boss_health(boss.health, boss.max_health)
	hud.set_boss_state(BuggyBoss.STATE_TEXT[boss.state])
	hud.set_touch_mode(touch_controls.active)
	hud.hide_dialog()
	koby.set_prompt("Toca «Hablar»" if touch_controls.active else "[E] Hablar")
	var data := SaveManager.take_pending()
	if data.is_empty():
		_refresh_checkpoints()
		# a new game: it replaces at once whatever the slot had
		if SaveManager.current_slot > 0:
			save_game(SaveManager.current_slot)
		hud.show_message("¡Habla con Koby!", 2.5)
	else:
		_apply_save(data)
		hud.show_message("Partida %d cargada" % SaveManager.current_slot, 2.0)
	_update_mission_text()
	_update_boss_hud()


func _process(delta: float) -> void:
	if not finished:
		elapsed += delta
	_keep_above_ground()
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
		pause_menu.can_save = not player.dead
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
		_update_boss_hud()
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
	collected_meat.append(str(item.name))
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
	# the bar shows Buggy's empty health for a moment and then goes away
	get_tree().create_timer(1.5).timeout.connect(_update_boss_hud)
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
	if won and SaveManager.current_slot > 0:
		SaveManager.write_slot(SaveManager.current_slot, collect_state(true))
	end_screen.show_result(won, elapsed, collected_items, total_items, boss.is_defeated())
	get_tree().paused = true


## Quality preset (Opciones): environment, sun shadows, camera distance, chunks and terrain.
func _apply_graphics() -> void:
	GraphicsSettings.apply_world(world_environment.environment, sun, player.camera, chunks)


# ------------------------------------------------------------------ checkpoints and saving
func _on_checkpoint_reached(cp: Checkpoint) -> void:
	if finished or cp.checkpoint_id == current_checkpoint:
		return
	if not activated_checkpoints.has(cp.checkpoint_id):
		activated_checkpoints.append(cp.checkpoint_id)
	current_checkpoint = cp.checkpoint_id
	player.heal(player.max_health)
	cp.play_activate_sound()
	_refresh_checkpoints()
	var saved := SaveManager.current_slot > 0 and save_game(SaveManager.current_slot)
	hud.show_message("Punto de control: %s%s" % [cp.display_name, "  ·  Partida guardada" if saved else ""], 2.0)


func _refresh_checkpoints() -> void:
	for cp in checkpoints.get_children():
		var c := cp as Checkpoint
		c.set_active(activated_checkpoints.has(c.checkpoint_id), c.checkpoint_id == current_checkpoint)


func _find_checkpoint(id: String) -> Checkpoint:
	for cp in checkpoints.get_children():
		if (cp as Checkpoint).checkpoint_id == id:
			return cp
	return null


## Everything that is saved in a slot (SaveManager validates and signs it).
func collect_state(completed := false) -> Dictionary:
	return {
		"play_time": int(elapsed),
		"health": clampi(ceili(player.health), 1, int(player.max_health)),
		"mission": mini(mission, Mission.ACTIVE),
		"completed": completed,
		"checkpoint": current_checkpoint,
		"checkpoints": activated_checkpoints.duplicate(),
		"meat": collected_meat.duplicate(),
		"boss_health": ceili(boss.health),
		"boss_defeated": boss.is_defeated(),
	}


func save_game(slot: int) -> bool:
	if player.dead or finished:
		return false
	var ok := SaveManager.write_slot(slot, collect_state())
	if ok:
		SaveManager.current_slot = slot
	return ok


## Pause menu -> "Guardar partida" -> a slot.
func _on_pause_menu_save_requested(slot: int) -> void:
	var ok := save_game(slot)
	pause_menu.show_saved(slot, ok)


## Restores a game loaded from a slot (the data was already checked by SaveManager).
func _apply_save(d: Dictionary) -> void:
	elapsed = float(d.play_time)
	mission = int(d.mission)
	koby.set_mission_given(mission >= Mission.ACTIVE)
	for n in d.meat:
		var meat := collectibles.get_node_or_null(NodePath(str(n)))
		if meat:
			collectibles.remove_child(meat)
			meat.queue_free()
	collected_meat = d.meat.duplicate()
	collected_items = collected_meat.size()
	hud.set_count(collected_items, total_items)
	boss.restore(float(d.boss_health))
	hud.set_boss_state(BuggyBoss.STATE_TEXT[boss.state])
	activated_checkpoints = d.checkpoints.duplicate()
	current_checkpoint = str(d.checkpoint)
	_refresh_checkpoints()
	player.health = float(d.health)
	player.health_changed.emit(player.health, player.max_health)
	var cp := _find_checkpoint(current_checkpoint)
	if cp:
		player.global_position = _on_ground(cp.spawn_transform().origin)
		player.velocity = Vector3.ZERO
		chunks.load_around(player.global_position)


## Buggy's health bar in the HUD: only while the mission is active and Buggy is still standing.
func _update_boss_hud() -> void:
	if is_inside_tree():
		hud.set_boss_visible(mission == Mission.ACTIVE and not boss.is_defeated())


## Height of the terrain at a point, read from its collision height map (it does not need the
## physics engine, so it also works in the first frame after loading a game).
## highest = true uses the highest corner of the cell: the result is never under the ground.
func ground_height(x: float, z: float, highest := false) -> float:
	var hm := terrain_shape.shape as HeightMapShape3D
	var xf := terrain_shape.global_transform
	var local := xf.affine_inverse() * Vector3(x, 0.0, z)
	var fx := clampf(local.x + (hm.map_width - 1) / 2.0, 0.0, hm.map_width - 1.001)
	var fz := clampf(local.z + (hm.map_depth - 1) / 2.0, 0.0, hm.map_depth - 1.001)
	var i := int(fz) * hm.map_width + int(fx)
	var h00 := hm.map_data[i]
	var h10 := hm.map_data[i + 1]
	var h01 := hm.map_data[i + hm.map_width]
	var h11 := hm.map_data[i + hm.map_width + 1]
	var h: float
	if highest:
		h = maxf(maxf(h00, h10), maxf(h01, h11))
	else:
		var tx := fx - int(fx)
		var tz := fz - int(fz)
		h = lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)
	return (xf * Vector3(local.x, h, local.z)).y


## A point moved up onto the ground if it is under it (respawn points on slopes).
func _on_ground(p: Vector3) -> Vector3:
	return Vector3(p.x, maxf(p.y, ground_height(p.x, p.z, true) + 0.15), p.z)


## The terrain collision only stops things from above: if Luffy ever ends under the island,
## he is put back on the ground.
func _keep_above_ground() -> void:
	var p := player.global_position
	if p.y < ground_height(p.x, p.z) - 1.5:
		player.global_position = Vector3(p.x, ground_height(p.x, p.z) + 0.3, p.z)
		player.velocity = Vector3.ZERO


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
