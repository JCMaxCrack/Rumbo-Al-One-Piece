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
## Zoro: in single player he is tied to a post in the north-west forest; with 3 pieces of meat
## he joins the crew (part of Koby's mission) and follows Luffy (CompanionAI). In local co-op
## (GameSession.coop) Zoro is player 2 from the start and the screen is split in two.
## Mini enemies (group "enemies", MiniEnemy) live in MiniEnemies; the HUD has a mini map.

enum Mission { NOT_GIVEN, ACTIVE, DONE }

@onready var player: Player = $Luffy
@onready var boss: BuggyBoss = $Buggy
@onready var koby: Koby = $Koby
@onready var zoro: Player = $Zoro
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
var zoro_recruited := false
var _dialog_speaker := "Koby"
var _split_viewports: Array[SubViewport] = []

const MEAT_FOR_ZORO := 3
const KOBY_ZORO_LINE := "One more thing: in the northwest forest the marines have tied up a swordsman, Roronoa Zoro for your crew!"
const KOBY_COOP_LINE := "¡How lucky that Zoro, the swordsman, is alreday traveling with you!"


func _ready() -> void:
	get_tree().paused = false
	get_viewport().disable_3d = false
	_setup_mode()
	_apply_graphics()
	GraphicsSettings.changed.connect(_apply_graphics)
	total_items = collectibles.get_child_count()
	hud.set_count(collected_items, total_items)
	hud.set_health(player.health, player.max_health)
	hud.set_boss_health(boss.health, boss.max_health)
	hud.set_boss_state(BuggyBoss.STATE_TEXT[boss.state])
	hud.set_touch_mode(touch_controls.active)
	hud.hide_dialog()
	koby.set_prompt("Press «Talk»" if touch_controls.active else "[E] Talk")
	var data := SaveManager.take_pending()
	if data.is_empty():
		_refresh_checkpoints()
		# a new game: it replaces at once whatever the slot had
		if SaveManager.current_slot > 0:
			save_game(SaveManager.current_slot)
		hud.show_message("¡Talk to Koby!", 2.5)
	else:
		_apply_save(data)
		hud.show_message("Game %d charged" % SaveManager.current_slot, 2.0)
	_update_mission_text()
	_update_boss_hud()
	_update_zoro()


func _exit_tree() -> void:
	get_viewport().disable_3d = false


# ------------------------------------------------------------------ single player / co-op
func _setup_mode() -> void:
	(zoro.get_node("CompanionAI") as CompanionAI).leader = player
	if GameSession.coop:
		zoro_recruited = true
		zoro.control = Player.Controller.PLAYER_TWO
		zoro.global_position = player.global_position + Vector3(1.6, 0.3, 0.8)
		chunks.extra_targets = [zoro]
		touch_controls.active = false
		_setup_split_screen()
	else:
		zoro.control = Player.Controller.NONE


## Co-op: two views side by side, each one following the camera of its player.
func _setup_split_screen() -> void:
	var layer := CanvasLayer.new()
	layer.name = "SplitScreen"
	layer.layer = -1
	add_child(layer)
	var box := HBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.add_theme_constant_override("separation", 4)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(box)
	for p in [player, zoro]:
		var container := SubViewportContainer.new()
		container.stretch = true
		container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		container.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(container)
		var vp := SubViewport.new()
		vp.world_3d = get_viewport().find_world_3d()
		vp.audio_listener_enable_3d = p == player
		container.add_child(vp)
		_split_viewports.append(vp)
		var cam := Camera3D.new()
		vp.add_child(cam)
		cam.current = true
		var follow := RemoteTransform3D.new()
		follow.name = "SplitScreenCamera"
		p.camera.add_child(follow)
		follow.remote_path = follow.get_path_to(cam)
	# the full screen view is not drawn: only the two halves
	get_viewport().disable_3d = true


## Zoro tied to the post, following Luffy, or player 2.
func _update_zoro() -> void:
	if GameSession.coop:
		hud.set_player2_visible(true)
		return
	zoro.control = Player.Controller.AI if zoro_recruited else Player.Controller.NONE
	$ZoroPost.visible = true
	hud.set_player2_visible(zoro_recruited)
	if zoro_recruited and zoro.global_position.distance_to(player.global_position) > 20.0:
		zoro.global_position = player.global_position - player.facing * 2.5 + Vector3(0, 0.4, 0)
	zoro.health_changed.emit(zoro.health, zoro.max_health)


func _zoro_near() -> bool:
	return not GameSession.coop and not zoro_recruited and zoro.global_position.distance_to(player.global_position) < 3.2


func _process(delta: float) -> void:
	if not finished:
		elapsed += delta
	_keep_above_ground()
	var near_zoro := _zoro_near()
	zoro.get_node("NameLabel").visible = not GameSession.coop and not zoro_recruited
	zoro.get_node("PromptLabel").visible = near_zoro and not hud.is_dialog_open()
	touch_controls.set_interact_visible(hud.is_dialog_open() or koby.player_near or near_zoro, "Follow" if hud.is_dialog_open() else "Talk")
	if DisplayServer.get_name() == "headless" or touch_controls.active:
		return
	var free_mouse := get_tree().paused or finished
	var want := Input.MOUSE_MODE_VISIBLE if free_mouse else Input.MOUSE_MODE_CAPTURED
	if Input.mouse_mode != want:
		Input.mouse_mode = want


func _unhandled_input(event: InputEvent) -> void:
	if finished:
		return
	var p2 := GameSession.coop
	if event.is_action_pressed("pause") or (p2 and event.is_action_pressed("p2_pause")):
		pause_menu.can_save = not player.dead
		pause_menu.toggle()
	elif event.is_action_pressed("toggle_debug"):
		boss.set_debug_visible(not boss.show_debug)
	elif event.is_action_pressed("map") or (p2 and event.is_action_pressed("p2_map")):
		hud.toggle_map()
	elif event.is_action_pressed("interact") or (p2 and event.is_action_pressed("p2_interact")):
		if hud.is_dialog_open():
			_next_dialog_line()
		elif koby.player_near:
			_talk_to_koby()
		elif _zoro_near():
			_talk_to_zoro()


# ------------------------------------------------------------------ Koby and the mission
func _talk_to_koby() -> void:
	match mission:
		Mission.NOT_GIVEN:
			_dialog = koby.mission_lines.duplicate()
			_dialog.append(KOBY_COOP_LINE if GameSession.coop else KOBY_ZORO_LINE)
		Mission.ACTIVE:
			_dialog = [_progress_line()]
		_:
			_dialog = ["¡You did it, Luffy-san! ¡You´r the best!"]
	_open_dialog("Koby")


func _open_dialog(speaker: String) -> void:
	_dialog_speaker = speaker
	_dialog_line = 0
	player.controls_enabled = false
	zoro.controls_enabled = false
	hud.show_dialog(speaker, _dialog[0], _dialog.size() == 1)


## Zoro, tied up: he joins the crew when Luffy has some meat for him.
func _talk_to_zoro() -> void:
	if collected_items >= MEAT_FOR_ZORO:
		_dialog = ["¡finally some food! ...Alright, i'll join your crew, But listen: my dream is to be the word's greatest swordsman. Don't forget that, Capitan!"]
	else:
		_dialog = ["And how are you? I'm Roronoa Zoro. the marines tied me up here, and I haven't eaten in day's...",
			"If you bring me %d meats , I'll join your crew (You have %d)" % [MEAT_FOR_ZORO, collected_items]]
	_open_dialog("Zoro")


func _next_dialog_line() -> void:
	_dialog_line += 1
	if _dialog_line < _dialog.size():
		hud.show_dialog(_dialog_speaker, _dialog[_dialog_line], _dialog_line == _dialog.size() - 1)
		return
	hud.hide_dialog()
	player.controls_enabled = true
	zoro.controls_enabled = true
	if _dialog_speaker == "Zoro":
		if collected_items >= MEAT_FOR_ZORO and not zoro_recruited:
			zoro_recruited = true
			_update_zoro()
			hud.show_message("¡Zoro joined the crew!", 2.0)
			_update_mission_text()
			_check_mission()
		return
	if mission == Mission.NOT_GIVEN:
		mission = Mission.ACTIVE
		koby.set_mission_given(true)
		hud.show_message("¡New mission!", 1.5)
		_update_mission_text()
		_update_boss_hud()
		_check_mission()


func _progress_line() -> String:
	var missing := []
	if not boss.is_defeated():
		missing.append("defeat Buggy in the crater")
	if collected_items < total_items:
		missing.append("collected %d meat more" % (total_items - collected_items))
	if not zoro_recruited:
		missing.append("recruit Zoro in the Northwest Forest")
	return "¡Go for it, Luffy-san! Todavía te falta " + " and ".join(missing) + "."


func _update_mission_text() -> void:
	if mission == Mission.NOT_GIVEN:
		hud.set_mission("Talk to Koby on the south beach")
		return
	var boss_mark := "[X]" if boss.is_defeated() else "[  ]"
	var meat_mark := "[X]" if collected_items >= total_items else "[  ]"
	var zoro_mark := "[X]" if zoro_recruited else "[  ]"
	var text := "%s Defeat Buggy the Clown's\n%s Collect the meat (%d/%d)" % [boss_mark, meat_mark, collected_items, total_items]
	if not GameSession.coop:
		text += "\n%s Recruit Zoro" % zoro_mark
	hud.set_mission(text)


func _check_mission() -> void:
	if mission == Mission.ACTIVE and boss.is_defeated() and collected_items >= total_items and zoro_recruited:
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
	if mission == Mission.ACTIVE and collected_items >= total_items and boss.is_defeated() and zoro_recruited:
		_check_mission()
	else:
		hud.show_message("¡MEAT! +%d health  (%d/%d)" % [int(item.heal_amount), collected_items, total_items], 1.2)


func _on_buggy_state_changed(new_state: int) -> void:
	if not is_node_ready():
		return
	hud.set_boss_state(BuggyBoss.STATE_TEXT[new_state])
	if finished or new_state == BuggyBoss.State.DEFEATED:
		return
	if new_state == BuggyBoss.State.CHASE:
		hud.show_message("¡Buggy see you!", 1.0)
		_crossfade(chase_music, explore_music)
	elif new_state == BuggyBoss.State.RETURN:
		hud.show_message("¡You escaped!", 1.0)
		_crossfade(explore_music, chase_music)


func _on_buggy_defeated() -> void:
	if not is_node_ready():
		return
	_crossfade(explore_music, chase_music)
	_update_mission_text()
	# the bar shows Buggy's empty health for a moment and then goes away
	get_tree().create_timer(1.5).timeout.connect(_update_boss_hud)
	if mission == Mission.ACTIVE and collected_items >= total_items and zoro_recruited:
		_check_mission()
	else:
		hud.show_message("¡You defeated Buggy the Clown!", 2.0)


func _on_player_died() -> void:
	if not is_node_ready():
		return
	if finished:
		return
	hud.show_message("¡Buggy defeated you!", 1.5)
	defeat_timer.start()


## Zoro fell (player 2 or companion): he comes back next to Luffy after a moment.
func _on_zoro_died() -> void:
	if finished:
		return
	hud.show_message("¡Zoro is wounded! He'll be back soon", 1.5)
	await get_tree().create_timer(3.0).timeout
	if is_inside_tree() and not finished:
		zoro.revive(_on_ground(player.global_position - player.facing * 2.0))


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
	# split screen: the two halves use the same quality as the full view
	var root := get_viewport()
	for vp in _split_viewports:
		vp.msaa_3d = root.msaa_3d
		vp.screen_space_aa = root.screen_space_aa
		vp.scaling_3d_mode = root.scaling_3d_mode
		vp.scaling_3d_scale = root.scaling_3d_scale
		vp.mesh_lod_threshold = root.mesh_lod_threshold
		vp.use_occlusion_culling = root.use_occlusion_culling
		var cam := vp.get_camera_3d()
		if cam:
			cam.far = player.camera.far
			cam.fov = player.camera.fov


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
	hud.show_message("Checkpoint: %s%s" % [cp.display_name, "  ·  Saved Game" if saved else ""], 2.0)


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
		"zoro": zoro_recruited,
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
	zoro_recruited = bool(d.get("zoro", false)) or GameSession.coop
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
