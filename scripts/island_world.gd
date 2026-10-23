class_name IslandWorld
extends Node3D
## Base of every island scene (scenes/game.tscn, scenes/islands/*.tscn). What all the islands share:
##   - single player / local co-op: the crew that already joined follows Luffy (CompanionAI), in
##     co-op Zoro is player 2 and the screen is split in two;
##   - talking (dialogues in the HUD) and the things that can be used with "interact": every island
##     says which ones with _interactables();
##   - inventory (use / change item), skills (use / change skill) and the skill shop;
##   - experience: every defeated enemy gives XP (GameState), every level gives a skill point;
##   - the boss of the island (health bar in the HUD, chase music);
##   - checkpoints and saving (SaveManager), the island progress lives in GameState.islands;
##   - the Going Merry: at its helm (ShipHelm) Luffy can sail to the islands already open.
## The scripts of each island extend this one and fill the virtual functions marked "island:".
## Nodes needed: Luffy, Collectibles, Checkpoints, Sun, WorldEnvironment,
## Island/TerrainBody/CollisionShape3D, HUD, TouchControls, PauseMenu, EndScreen, ExploreMusic,
## ChaseMusic, VictorySound, DefeatSound, DefeatTimer. Optional: ChunkManager, ShipHelm, PlayerStart.

enum Mission { NOT_GIVEN, ACTIVE, DONE }

const CREW_SCENES := {"zoro": "res://scenes/player/zoro.tscn", "usopp": "res://scenes/player/usopp.tscn", "nami": "res://scenes/player/nami.tscn"}
const SKILL_SHOP_SCENE := "res://scenes/ui/skill_shop.tscn"
const SAIL_MENU_SCENE := "res://scenes/ui/sail_menu.tscn"

## Id of the island (GameState.ISLANDS, SaveManager.ISLAND_SPECS).
@export var island_id := "isla_inicio"
## Crew member that joins in this island ("" = none).
@export var recruit_member := ""
## false when the scene itself connects the boss signals (the first island does).
@export var connect_boss_signals := true
## Top view of the island for the minimap (the first island keeps the one of the HUD) and the
## side of the area it shows, in meters.
@export var minimap_texture: Texture2D
@export var world_size := 440.0

@onready var player: Player = $Luffy
@onready var collectibles: Node3D = $Collectibles
@onready var checkpoints: Node3D = $Checkpoints
@onready var chunks: ChunkManager = get_node_or_null("ChunkManager")
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
@onready var ship_helm: Node3D = get_node_or_null("ShipHelm")

## The boss of the island (BuggyBoss or Boss), set by the island in _island_ready().
var boss: Node3D
## Crew members in the scene: "zoro" -> Player...
var crew_nodes := {}
var mission: int = Mission.NOT_GIVEN
## The crew member of this island already joined.
var recruited := false
var total_items := 0
## Names of the pickups already taken (they are saved).
var collected_items: Array = []
## Things that happened in the island that the island script needs to remember (they are saved,
## SaveManager.ISLAND_SPECS lists the valid ones), e.g. "gate_open".
var flags: Array = []
var finished := false
var current_checkpoint := ""
var activated_checkpoints: Array = []
var skill_shop: SkillShop
var sail_menu: SailMenu
var _dialog: PackedStringArray = []
var _dialog_line := 0
var _dialog_speaker := ""
var _dialog_done := Callable()
var _music_tween: Tween
var _split_viewports: Array[SubViewport] = []
var _interact_target: Array = []
var _sailing := false


func _ready() -> void:
	get_tree().paused = false
	get_viewport().disable_3d = false
	GameState.island = island_id
	if not GameState.unlocked.has(island_id):
		GameState.unlocked.append(island_id)
	var first: Checkpoint = checkpoints.get_child(0)
	current_checkpoint = first.checkpoint_id
	activated_checkpoints = [current_checkpoint]
	_island_ready()
	_setup_crew()
	_apply_graphics()
	GraphicsSettings.changed.connect(_apply_graphics)
	_connect_nodes()
	total_items = collectibles.get_child_count()
	skill_shop = (load(SKILL_SHOP_SCENE) as PackedScene).instantiate()
	add_child(skill_shop)
	skill_shop.closed.connect(_on_menu_closed)
	sail_menu = (load(SAIL_MENU_SCENE) as PackedScene).instantiate()
	add_child(sail_menu)
	sail_menu.closed.connect(_on_menu_closed)
	sail_menu.sail_requested.connect(sail_to)
	if minimap_texture:
		hud.minimap.map_texture = minimap_texture
		hud.minimap.world_size = world_size
	hud.set_touch_mode(touch_controls.active)
	hud.hide_dialog()
	player.set_max_health(_luffy_max_health(), true)
	var loaded := SaveManager.take_pending()
	var st: Dictionary = GameState.islands.get(island_id, {})
	if st.is_empty():
		_refresh_checkpoints()
		_spawn_at_start()
	else:
		_apply_island(st)
	if GameState.health > 0.0:
		player.health = minf(GameState.health, player.max_health)
		player.health_changed.emit(player.health, player.max_health)
	hud.set_health(player.health, player.max_health)
	if loaded.is_empty() and st.is_empty() and SaveManager.current_slot > 0:
		save_game(SaveManager.current_slot)
	_update_hud_state()
	_update_mission_text()
	_update_boss_hud()
	_update_crew()
	GameState.inventory_changed.connect(_on_inventory_changed)
	GameState.xp_changed.connect(_on_xp_changed)
	GameState.leveled_up.connect(_on_leveled_up)
	GameState.skills_changed.connect(_on_skills_changed)
	_arrival_message(not loaded.is_empty())


func _exit_tree() -> void:
	get_viewport().disable_3d = false
	GameState.health = player.health if is_instance_valid(player) and not player.dead else 0.0


# ------------------------------------------------------------------ island: virtual functions
## island: find its nodes (boss, NPCs...). Called before anything else.
func _island_ready() -> void:
	pass


## island: [[node, radius, prompt, callable], ...] that can be used with "interact" right now.
func _interactables() -> Array:
	var out := []
	if ship_helm and not _sailing:
		out.append([ship_helm, 2.8, "Zarpar", _open_sail_menu])
	return out


## island: text of the mission in the HUD.
func _mission_text() -> String:
	return ""


## island: are all the goals of the mission done?
func _mission_goals_done() -> bool:
	return false


## island: the boss was defeated (besides the shared part: music, HUD, XP).
func _on_boss_down() -> void:
	pass


## island: restore its own nodes from a saved progress (after the shared part).
func _apply_island_extra(_st: Dictionary) -> void:
	pass


## island: message when the island starts.
func _arrival_message(loaded: bool) -> void:
	if loaded:
		hud.show_message(tr("Partida %d cargada") % SaveManager.current_slot, 2.0)
	else:
		hud.show_message(tr(GameState.ISLAND_NAMES[island_id]), 2.5)


# ------------------------------------------------------------------ crew and co-op
func _setup_crew() -> void:
	for member in GameState.CREW:
		var node := get_node_or_null(member.capitalize()) as Player
		var wanted: bool = GameState.has_crew(member) or (member == "zoro" and GameState.coop_zoro())
		if node == null and wanted:
			node = (load(CREW_SCENES[member]) as PackedScene).instantiate() as Player
			node.name = member.capitalize()
			add_child(node)
			node.global_position = _on_ground(player.global_position - player.facing * (2.0 + crew_nodes.size()) + Vector3(1.2 * crew_nodes.size(), 0.3, 0))
		if node:
			crew_nodes[member] = node
			var ai := node.get_node_or_null("CompanionAI") as CompanionAI
			if ai:
				ai.leader = player
			if not node.died.is_connected(_on_crew_died):
				node.died.connect(_on_crew_died.bind(node))
	var zoro := crew_nodes.get("zoro") as Player
	if zoro and not zoro.health_changed.is_connected(hud.set_health2):
		zoro.health_changed.connect(hud.set_health2)
	if GameState.coop_zoro() and zoro:
		zoro.control = Player.Controller.PLAYER_TWO
		zoro.global_position = player.global_position + Vector3(1.6, 0.3, 0.8)
		if chunks:
			chunks.extra_targets = [zoro]
		touch_controls.active = false
		_setup_split_screen()


## Who follows Luffy, who is player 2 and who still waits in the island.
func _update_crew() -> void:
	for member in crew_nodes:
		var p: Player = crew_nodes[member]
		if member == "zoro" and GameState.coop_zoro():
			p.control = Player.Controller.PLAYER_TWO
			continue
		var joined: bool = GameState.has_crew(member) or (member == recruit_member and recruited)
		p.control = Player.Controller.AI if joined else Player.Controller.NONE
		var label := p.get_node_or_null("NameLabel") as Label3D
		if label:
			label.visible = not joined
		if joined and p.global_position.distance_to(player.global_position) > 25.0:
			p.global_position = _on_ground(player.global_position - player.facing * 2.5)
	var zoro := crew_nodes.get("zoro") as Player
	hud.set_player2_visible(zoro != null and zoro.control != Player.Controller.NONE)
	if zoro:
		zoro.health_changed.emit(zoro.health, zoro.max_health)


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
	for p in [player, crew_nodes.zoro]:
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
		(p as Player).camera.add_child(follow)
		follow.remote_path = follow.get_path_to(cam)
	get_viewport().disable_3d = true


## A crew member fell (player 2 or companion): he comes back next to Luffy after a moment.
func _on_crew_died(p: Player) -> void:
	if finished:
		return
	hud.show_message(tr("¡%s cayó! Volverá en un momento") % p.display_name, 1.5)
	await get_tree().create_timer(3.0).timeout
	if is_inside_tree() and not finished and is_instance_valid(p):
		p.revive(_on_ground(player.global_position - player.facing * 2.0))


# ------------------------------------------------------------------ frame and input
func _process(delta: float) -> void:
	if not finished and not get_tree().paused:
		GameState.play_time += delta
	_keep_above_ground()
	_update_interact_target()
	hud.set_skill(GameState.equipped, player.skill_cooldown(GameState.equipped) / maxf(0.01, float(GameState.SKILLS.get(GameState.equipped, {"cooldown": 1.0}).cooldown)))
	if DisplayServer.get_name() == "headless" or touch_controls.active:
		return
	var free_mouse := get_tree().paused or finished
	var want := Input.MOUSE_MODE_VISIBLE if free_mouse else Input.MOUSE_MODE_CAPTURED
	if Input.mouse_mode != want:
		Input.mouse_mode = want


## The closest thing that can be used with "interact" (its prompt is shown).
func _update_interact_target() -> void:
	var best: Array = []
	var best_d := INF
	if not hud.is_dialog_open() and not finished and not player.dead:
		for it in _interactables():
			var n := it[0] as Node3D
			if n == null or not is_instance_valid(n) or not n.is_visible_in_tree():
				continue
			var d := n.global_position.distance_to(player.global_position)
			if d < float(it[1]) and d < best_d:
				best = it
				best_d = d
	_interact_target = best
	var label := tr(best[2]) if not best.is_empty() else ""
	hud.set_interact_hint(label)
	touch_controls.set_interact_visible(hud.is_dialog_open() or not best.is_empty(), tr("Seguir") if hud.is_dialog_open() else (label if label != "" else tr("Hablar")))


func _unhandled_input(event: InputEvent) -> void:
	if finished or _sailing:
		return
	var p2 := GameState.coop_zoro()
	if event.is_action_pressed("pause") or (p2 and event.is_action_pressed("p2_pause")):
		pause_menu.can_save = not player.dead
		pause_menu.toggle()
	elif event.is_action_pressed("map") or (p2 and event.is_action_pressed("p2_map")):
		hud.toggle_map()
	elif event.is_action_pressed("interact") or (p2 and event.is_action_pressed("p2_interact")):
		if hud.is_dialog_open():
			_next_dialog_line()
		elif not _interact_target.is_empty():
			(_interact_target[3] as Callable).call()
	elif hud.is_dialog_open():
		return
	elif event.is_action_pressed("use_item"):
		_use_selected_item()
	elif event.is_action_pressed("next_item"):
		GameState.select_next()
	elif event.is_action_pressed("skill"):
		_use_skill()
	elif event.is_action_pressed("next_skill"):
		GameState.equip_next()
		if GameState.equipped != "":
			hud.show_message(GameState.skill_name(GameState.equipped), 1.0)
	elif event.is_action_pressed("shop"):
		open_skill_shop()
	elif event is InputEventKey and event.pressed and not event.echo:
		var k := (event as InputEventKey).physical_keycode
		if k >= KEY_1 and k <= KEY_4:
			GameState.select_slot(k - KEY_1)


func _use_selected_item() -> void:
	var id := GameState.selected_item()
	if id == "":
		hud.show_message(tr("No tienes nada en esa casilla"), 1.2)
		return
	var heal: float = GameState.ITEMS[id].heal
	if heal <= 0.0:
		hud.show_message(tr("%s: se usa en otro lugar") % GameState.item_name(id), 1.5)
		return
	if player.health >= player.max_health:
		hud.show_message(tr("Ya tienes toda la vida"), 1.2)
		return
	if player.eat(id, heal):
		GameState.remove_item(id)


func _use_skill() -> void:
	if GameState.equipped == "":
		hud.show_message(tr("Aprende ataques en la tienda de habilidades (K)"), 1.8)
		return
	if not player.use_skill(GameState.equipped):
		var cd := player.skill_cooldown(GameState.equipped)
		if cd > 0.0:
			hud.show_message(tr("%s: espera %.1f s") % [GameState.skill_name(GameState.equipped), cd], 0.9)


func open_skill_shop() -> void:
	if finished or player.dead or get_tree().paused:
		return
	skill_shop.open()


func _on_menu_closed() -> void:
	if not skill_shop.visible and not sail_menu.visible and not pause_menu.visible:
		get_tree().paused = false


# ------------------------------------------------------------------ dialogues
## Shows lines in the HUD; on_done is called after the last one.
func open_dialog(speaker: String, lines: Array, on_done := Callable()) -> void:
	_dialog = PackedStringArray(lines.map(func(l): return tr(l)))
	_dialog_speaker = speaker
	_dialog_done = on_done
	_dialog_line = 0
	for p in [player] + crew_nodes.values():
		(p as Player).controls_enabled = false
	hud.show_dialog(speaker, _dialog[0], _dialog.size() == 1)


func _next_dialog_line() -> void:
	_dialog_line += 1
	if _dialog_line < _dialog.size():
		hud.show_dialog(_dialog_speaker, _dialog[_dialog_line], _dialog_line == _dialog.size() - 1)
		return
	hud.hide_dialog()
	for p in [player] + crew_nodes.values():
		(p as Player).controls_enabled = true
	if _dialog_done.is_valid():
		var done := _dialog_done
		_dialog_done = Callable()
		done.call()


# ------------------------------------------------------------------ mission
func _update_mission_text() -> void:
	hud.set_mission(_mission_text())


## Checks the goals; when they are all done the island is completed.
func check_mission() -> void:
	if mission == Mission.ACTIVE and _mission_goals_done():
		_complete_island()


func _complete_island() -> void:
	mission = Mission.DONE
	GameState.complete_island(island_id)
	GameState.add_xp(50)
	_update_mission_text()
	if GameState.is_last_island(island_id):
		_finish(true)
		return
	victory_sound.play()
	var nxt := GameState.next_island(island_id)
	hud.show_banner(tr("¡Isla completada!"), tr("Sube al Going Merry y usa el timón para zarpar hacia %s") % tr(GameState.ISLAND_NAMES[nxt]), 6.0)
	if SaveManager.current_slot > 0:
		save_game(SaveManager.current_slot)


# ------------------------------------------------------------------ enemies, experience and boss
func _connect_nodes() -> void:
	for e in get_tree().get_nodes_in_group("enemies"):
		if e is MiniEnemy:
			(e as MiniEnemy).defeated.connect(func(_x): _award_xp(e))
		elif e.has_signal("defeated"):
			e.connect("defeated", func(): _award_xp(e))
	if boss and connect_boss_signals:
		boss.connect("state_changed", _on_boss_state_changed)
		boss.connect("defeated", _on_boss_defeated)
		boss.connect("health_changed", hud.set_boss_health)
		if boss.has_signal("taunt"):
			boss.connect("taunt", func(t: String): hud.show_message(tr(t), 1.4))
	for c in collectibles.get_children():
		var item := c as Collectible
		if item == null:
			continue
		if not item.collected.is_connected(_on_item_collected):
			item.collected.connect(_on_item_collected)
		item.rejected.connect(func(_i): hud.show_message(tr("¡Inventario lleno! Come algo para hacer sitio (Q)"), 1.6))
	for cp in checkpoints.get_children():
		var c2 := cp as Checkpoint
		if not c2.reached.is_connected(_on_checkpoint_reached):
			c2.reached.connect(_on_checkpoint_reached)
	if not player.died.is_connected(_on_player_died):
		player.died.connect(_on_player_died)
	if not player.health_changed.is_connected(hud.set_health):
		player.health_changed.connect(hud.set_health)
	if boss:
		hud.set_boss_name(tr(boss.get("display_name")))
		hud.set_boss_health(boss.get("health"), boss.get("max_health"))


func _award_xp(e: Node) -> void:
	var amount := int(e.get("xp_reward")) if e.get("xp_reward") != null else 10
	GameState.add_xp(amount)
	if is_instance_valid(e) and e is Node3D:
		FX.text(self, (e as Node3D).global_position + Vector3(0, 2.2, 0), "+%d XP" % amount, Color(0.6, 0.9, 1.0), 44)


func _on_xp_changed(level: int, xp: int, needed: int) -> void:
	hud.set_xp(level, xp, needed, GameState.skill_points)


func _on_leveled_up(level: int) -> void:
	player.set_max_health(_luffy_max_health(), true)
	FX.level_up(self, player.global_position)
	FX.text(self, player.global_position + Vector3(0, 2.4, 0), tr("¡Nivel %d!") % level, Color(1, 0.85, 0.3), 64, 1.6)
	hud.show_message(tr("¡Subiste al nivel %d! Tienes %d punto(s) de habilidad: abre la tienda (K)") % [level, GameState.skill_points], 3.0)
	hud.set_xp(level, GameState.xp, GameState.xp_needed(), GameState.skill_points)


func _on_skills_changed() -> void:
	hud.set_xp(GameState.level, GameState.xp, GameState.xp_needed(), GameState.skill_points)


func _on_inventory_changed() -> void:
	hud.set_inventory(GameState.inventory, GameState.selected_slot)


func _luffy_max_health() -> float:
	return SaveManager.PLAYER_MAX_HEALTH + SaveManager.HEALTH_PER_LEVEL * (GameState.level - 1)


func _update_hud_state() -> void:
	_on_inventory_changed()
	_on_xp_changed(GameState.level, GameState.xp, GameState.xp_needed())
	hud.set_count(_meat_taken(), _meat_total())


func _meat_total() -> int:
	var n := 0
	for c in collectibles.get_children():
		if (c as Collectible).item_id == "meat":
			n += 1
	return n + _meat_taken()


func _meat_taken() -> int:
	var n := 0
	for name in collected_items:
		if str(name).begins_with("Meat"):
			n += 1
	return n


func _on_boss_state_changed(new_state: int) -> void:
	if not is_node_ready():
		return
	hud.set_boss_state(tr(boss.call("state_text")) if boss.has_method("state_text") else "")
	if finished or boss.call("is_defeated"):
		return
	var chasing := ["¡Persiguiendo!", "¡Te vio!", "¡Atacando!", "¡Ataque especial!"].has(boss.call("state_text"))
	if chasing and not chase_music.playing:
		hud.show_message(tr("¡%s te vio!") % tr(boss.get("display_name")), 1.0)
		_crossfade(chase_music, explore_music)
	elif not chasing and chase_music.playing and boss.call("state_text") == "Regresando":
		hud.show_message(tr("¡Escapaste!"), 1.0)
		_crossfade(explore_music, chase_music)
	_update_boss_hud()


func _on_boss_defeated() -> void:
	if not is_node_ready():
		return
	_crossfade(explore_music, chase_music)
	hud.show_message(tr("¡Derrotaste a %s!") % tr(boss.get("display_name")), 2.0)
	get_tree().create_timer(1.5).timeout.connect(_update_boss_hud)
	_update_mission_text()
	_on_boss_down()
	check_mission()


## The boss bar is shown while the mission is active, or while the boss is chasing.
func _update_boss_hud() -> void:
	if is_inside_tree() and boss:
		var fighting: bool = boss.has_method("state_text") and ["¡Persiguiendo!", "¡Te vio!", "¡Atacando!", "¡Ataque especial!"].has(boss.call("state_text"))
		hud.set_boss_visible((mission == Mission.ACTIVE or fighting) and not boss.call("is_defeated"))


func _on_player_died() -> void:
	if not is_node_ready() or finished:
		return
	hud.show_message(tr("¡Te derrotaron!"), 1.5)
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
	end_screen.show_result(won, GameState.play_time, _meat_taken(), _meat_total(), boss != null and boss.call("is_defeated"))
	get_tree().paused = true


# ------------------------------------------------------------------ pickups
func _on_item_collected(item: Collectible) -> void:
	if not is_node_ready():
		return
	collected_items.append(str(item.name))
	hud.set_count(_meat_taken(), _meat_total())
	_update_mission_text()
	hud.show_message(tr("¡%s! Guardada en el inventario (Q para comer)") % GameState.item_name(item.item_id) if GameState.ITEMS[item.item_id].heal > 0.0 else tr("¡%s!") % GameState.item_name(item.item_id), 1.4)
	_on_item_taken(item)
	check_mission()


## island: something was picked up.
func _on_item_taken(_item: Collectible) -> void:
	pass


# ------------------------------------------------------------------ graphics
func _apply_graphics() -> void:
	GraphicsSettings.apply_world(world_environment.environment, sun, player.camera, chunks)
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
	hud.show_message(tr("Punto de control: %s") % tr(cp.display_name) + ("  ·  " + tr("Partida guardada") if saved else ""), 2.0)


func _refresh_checkpoints() -> void:
	for cp in checkpoints.get_children():
		var c := cp as Checkpoint
		c.set_active(activated_checkpoints.has(c.checkpoint_id), c.checkpoint_id == current_checkpoint)


func _find_checkpoint(id: String) -> Checkpoint:
	for cp in checkpoints.get_children():
		if (cp as Checkpoint).checkpoint_id == id:
			return cp
	return null


## Progress of this island (SaveManager validates it, see _valid_island()).
func collect_island() -> Dictionary:
	return {
		"mission": mission,
		"checkpoint": current_checkpoint,
		"checkpoints": activated_checkpoints.duplicate(),
		"items": collected_items.duplicate(),
		"boss_health": ceili(boss.get("health")) if boss else 0,
		"boss_defeated": boss.call("is_defeated") if boss else true,
		"recruited": recruited,
		"flags": flags.duplicate(),
	}


## Everything that is saved in a slot.
func collect_state(completed := false) -> Dictionary:
	GameState.islands[island_id] = collect_island()
	return {
		"play_time": int(GameState.play_time),
		"completed": completed,
		"island": island_id,
		"health": clampi(ceili(player.health), 1, int(player.max_health)),
		"player": GameState.collect(),
		"islands": GameState.islands.duplicate(true),
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


## Restores the progress of the island.
func _apply_island(st: Dictionary) -> void:
	mission = int(st.mission)
	for n in st.items:
		var it := collectibles.get_node_or_null(NodePath(str(n)))
		if it:
			collectibles.remove_child(it)
			it.queue_free()
	collected_items = (st.items as Array).duplicate()
	if boss:
		boss.call("restore", float(st.boss_health))
	recruited = bool(st.recruited)
	flags = (st.get("flags", []) as Array).duplicate()
	activated_checkpoints = (st.checkpoints as Array).duplicate()
	current_checkpoint = str(st.checkpoint)
	_refresh_checkpoints()
	var cp := _find_checkpoint(current_checkpoint)
	if cp:
		player.global_position = _on_ground(cp.spawn_transform().origin)
		player.velocity = Vector3.ZERO
		if chunks:
			chunks.load_around(player.global_position)
	_apply_island_extra(st)


func _spawn_at_start() -> void:
	var start := get_node_or_null("PlayerStart") as Node3D
	var p := start.global_position if start else (checkpoints.get_child(0) as Checkpoint).spawn_transform().origin
	player.global_position = _on_ground(p)
	player.velocity = Vector3.ZERO
	if chunks:
		chunks.load_around(player.global_position)


# ------------------------------------------------------------------ sailing
func _open_sail_menu() -> void:
	sail_menu.open(island_id)


## Sails with the Going Merry to another island (it must be open).
func sail_to(id: String) -> void:
	if not GameState.unlocked.has(id) or id == island_id or _sailing:
		return
	_sailing = true
	GameState.islands[island_id] = collect_island()
	GameState.health = player.health
	GameState.island = id
	if SaveManager.current_slot > 0:
		var doc := collect_state()
		doc.island = id
		GameState.islands[island_id] = collect_island()
		SaveManager.write_slot(SaveManager.current_slot, doc)
	hud.show_banner(tr("Zarpando..."), tr("Rumbo a %s") % tr(GameState.ISLAND_NAMES[id]), 2.0)
	var tw := create_tween()
	tw.tween_interval(1.8)
	tw.tween_callback(func(): get_tree().change_scene_to_file(GameState.island_scene(id)))


# ------------------------------------------------------------------ ground
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
