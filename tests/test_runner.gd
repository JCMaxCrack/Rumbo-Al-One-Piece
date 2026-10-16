extends Node
## Automatic test of the beta. Run: godot --headless --path . res://tests/test_runner.tscn
## Not part of the game (excluded from the export).

var world: Node
var errors := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	await _test_scene_nodes()
	await _test_boss_and_jump()
	await _test_victory()
	await _test_defeat()
	print("[TEST] finished with %d errors" % errors)
	get_tree().quit(errors)


func _load_world() -> void:
	if world:
		world.queue_free()
		await get_tree().process_frame
	get_tree().paused = false
	world = load("res://scenes/game.tscn").instantiate()
	get_tree().root.add_child(world)
	await _frames(20)


func _test_scene_nodes() -> void:
	await _load_world()
	var luffy: Player = world.get_node("Luffy")
	var buggy: BuggyBoss = world.get_node("Buggy")
	for p in ["CollisionShape3D", "Model", "AnimationPlayer", "CameraPivot/SpringArm3D/Camera3D", "InvulnerabilityTimer", "HurtTimer"]:
		_check(luffy.has_node(p), "Luffy scene has node " + p)
	for p in ["CollisionShape3D", "Model/BuggyModel", "AnimationPlayer", "DetectionArea/CollisionShape3D", "ChaseLimitArea/CollisionShape3D", "AttackArea/CollisionShape3D", "PunchHitbox/CollisionShape3D", "PatrolPauseTimer", "LoseTimer", "AttackCooldown"]:
		_check(buggy.has_node(p), "Buggy scene has node " + p)
	var lap: AnimationPlayer = luffy.get_node("AnimationPlayer")
	_check(lap.has_animation("luffy/idle") and lap.has_animation("luffy/run") and lap.has_animation("luffy/jump") and lap.has_animation("luffy/hurt"), "Luffy AnimationPlayer has idle/run/jump/hurt")
	var bap: AnimationPlayer = buggy.get_node("AnimationPlayer")
	_check(bap.has_animation("buggy/punch") and bap.has_animation("buggy/walk"), "Buggy AnimationPlayer has walk/punch")
	_check(buggy.patrol_left != null and buggy.patrol_right != null and buggy.target == luffy, "Buggy exports point to the markers and to Luffy")
	_check(world.get_node("Collectibles").get_child_count() == 5, "5 collectibles in the level")
	var meat: Collectible = world.get_node("Collectibles/Meat1")
	_check(meat.get_signal_connection_list("collected").size() == 1 and meat.get_signal_connection_list("body_entered").size() == 1, "meat signals connected once (from the scene)")
	_check(not luffy.get_node("Model").has_node("Camera") and not luffy.get_node("Model").has_node("Light"), "FBX camera/light not imported")


func _test_boss_and_jump() -> void:
	var boss: BuggyBoss = world.get_node("Buggy")
	var player: Player = world.get_node("Luffy")
	_check(boss.state == BuggyBoss.State.PATROL, "boss starts in PATROL")
	var xs := []
	var z0 := boss.global_position.z
	for i in 12:
		await _time(1.0)
		xs.append(snappedf(boss.global_position.x, 0.1))
	print("[TEST] patrol x: ", xs)
	_check(xs.max() - xs.min() > 15.0, "patrol covers the line (%.1f m)" % (xs.max() - xs.min()))
	_check(absf(boss.global_position.z - z0) < 0.5, "patrol stays on the line (z)")
	player.global_position = boss.global_position + Vector3(0, 0.5, 7.0)
	await _time(0.4)
	_check(boss.state == BuggyBoss.State.CHASE or boss.state == BuggyBoss.State.ATTACK, "boss detects the player and chases (state %d)" % boss.state)
	_check(world.get_node("HUD/Root/Message").visible, "HUD shows the 'Buggy te vio' message")
	var hp_before := player.health
	await _time(3.5)
	_check(player.health < hp_before, "boss punch hits the player (health %d)" % player.health)
	player.global_position = boss.global_position + Vector3(0, 0.5, 26.0)
	await _time(2.5)
	_check(boss.state == BuggyBoss.State.RETURN or boss.state == BuggyBoss.State.PATROL, "boss stops chasing when the player escapes (state %d)" % boss.state)
	player.global_position = world.get_node("PlayerStart").global_position + Vector3(0, 0.3, 0)
	await _time(8.0)
	_check(boss.state == BuggyBoss.State.PATROL, "boss goes back to PATROL")
	_check(absf(boss.global_position.z - z0) < 1.0, "boss is back on the patrol line")
	# single jump: the hips must not rise inside the animation
	await _time(1.0)
	var sk: Skeleton3D = player.get_node("Model/Skeleton3D")
	var hips := -1
	for b in sk.get_bone_count():
		if sk.get_bone_name(b).ends_with("Hips"):
			hips = b
	var rest_y := sk.get_bone_rest(hips).origin.y
	Input.action_press("jump")
	await _frames(2)
	Input.action_release("jump")
	var max_rel := -INF
	var max_body := -INF
	var start_y := player.global_position.y
	for i in 40:
		await get_tree().physics_frame
		max_rel = maxf(max_rel, sk.get_bone_pose_position(hips).y - rest_y)
		max_body = maxf(max_body, player.global_position.y - start_y)
	_check(max_body > 0.8, "player jumps with physics (%.2f m)" % max_body)
	_check(max_rel <= absf(rest_y) * 0.03, "jump animation does not lift the hips again (%.2f of %.1f)" % [max_rel, rest_y])


func _test_victory() -> void:
	await _load_world()
	var player: Player = world.get_node("Luffy")
	var boss: BuggyBoss = world.get_node("Buggy")
	boss.process_mode = Node.PROCESS_MODE_DISABLED
	var items := world.get_node("Collectibles").get_children()
	for item in items:
		player.global_position = (item as Node3D).global_position + Vector3(0, 0.2, 0)
		player.velocity = Vector3.ZERO
		await _frames(8)
	await _frames(5)
	_check(world.collected_items == 5, "all 5 meats collected (%d)" % world.collected_items)
	_check(world.finished and get_tree().paused, "game ends when everything is collected")
	_check(world.get_node("EndScreen").visible and world.get_node("EndScreen/Panel/VBox/Title").text.contains("lograste"), "end screen shows the victory: " + world.get_node("EndScreen/Panel/VBox/Title").text)


func _test_defeat() -> void:
	await _load_world()
	var player: Player = world.get_node("Luffy")
	player.receive_hit(999.0, player.global_position + Vector3.FORWARD)
	_check(player.dead, "player dies at 0 health")
	await _time(2.5)
	_check(world.finished, "game ends after being caught")
	_check(world.get_node("EndScreen").visible and not world.get_node("EndScreen/Panel/VBox/Title").text.contains("lograste"), "end screen shows the defeat: " + world.get_node("EndScreen/Panel/VBox/Title").text)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _time(sec: float) -> void:
	await get_tree().create_timer(sec, true, true).timeout


func _check(ok: bool, msg: String) -> void:
	if ok:
		print("[OK]   ", msg)
	else:
		errors += 1
		print("[FAIL] ", msg)
