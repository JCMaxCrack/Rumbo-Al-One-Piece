extends Node3D
## Main beta scene logic (scenes/game.tscn).
## Goal: pick up every piece of meat without being caught by Buggy.
## Signals from Luffy, Buggy and the collectibles are connected in the scene.

@onready var player: Player = $Luffy
@onready var boss: BuggyBoss = $Buggy
@onready var collectibles: Node3D = $Collectibles
@onready var hud: HUD = $HUD
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
var _music_tween: Tween


func _ready() -> void:
	get_tree().paused = false
	total_items = collectibles.get_child_count()
	hud.set_count(collected_items, total_items)
	hud.set_health(player.health, player.max_health)
	hud.set_boss_state(BuggyBoss.STATE_TEXT[boss.state])
	hud.show_message("¡Recoge toda la carne sin que Buggy te atrape!", 2.5)


func _process(delta: float) -> void:
	if not finished:
		elapsed += delta
	if DisplayServer.get_name() == "headless":
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


func _on_item_collected(_item: Collectible) -> void:
	if not is_node_ready():
		return
	collected_items += 1
	hud.set_count(collected_items, total_items)
	if collected_items >= total_items:
		_finish(true)
	else:
		hud.show_message("¡Carne! (%d/%d)" % [collected_items, total_items], 1.0)


func _on_buggy_state_changed(new_state: int) -> void:
	if not is_node_ready():
		return
	hud.set_boss_state(BuggyBoss.STATE_TEXT[new_state])
	if finished:
		return
	if new_state == BuggyBoss.State.CHASE:
		hud.show_message("¡Buggy te vio!", 1.0)
		_crossfade(chase_music, explore_music)
	elif new_state == BuggyBoss.State.RETURN:
		hud.show_message("¡Escapaste!", 1.0)
		_crossfade(explore_music, chase_music)


func _on_player_died() -> void:
	if not is_node_ready():
		return
	if finished:
		return
	hud.show_message("¡Buggy te atrapó!", 1.5)
	defeat_timer.start()


func _on_defeat_timer_timeout() -> void:
	_finish(false)


func _finish(won: bool) -> void:
	finished = true
	player.controls_enabled = false
	explore_music.stop()
	chase_music.stop()
	if won:
		victory_sound.play()
	else:
		defeat_sound.play()
	end_screen.show_result(won, elapsed, collected_items, total_items)
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
