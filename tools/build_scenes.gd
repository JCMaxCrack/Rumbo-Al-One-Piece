extends Node
## EDITOR TOOL (not used while playing). Generates every scene of the beta with all its nodes:
##   scenes/player/luffy.tscn, scenes/enemies/buggy.tscn, scenes/items/meat.tscn,
##   scenes/ui/*.tscn, scenes/main_menu.tscn and scenes/game.tscn.
## Run it once with: godot --headless --path . res://tools/build_scenes.tscn
## After that, everything can be edited by hand in the Godot editor.

const AUDIO := "res://assets/audio/"
var theme: Theme


func _ready() -> void:
	_input_map()
	theme = UITheme.make()
	_save(theme, "res://assets/ui/theme.tres")
	_build_luffy()
	_build_buggy()
	_build_meat()
	_build_hud()
	_build_pause_menu()
	_build_end_screen()
	_build_main_menu()
	_build_game()
	print("BUILD OK")
	get_tree().quit()


# ------------------------------------------------------------------ helpers
func _save(res: Resource, path: String) -> void:
	if res is Mesh:
		var m := res as Mesh
		for i in m.get_surface_count():
			var mat := m.surface_get_material(i)
			if mat:
				_save_material(mat)
		if res is PrimitiveMesh and (res as PrimitiveMesh).material:
			_save_material((res as PrimitiveMesh).material)
	var err := ResourceSaver.save(res, path)
	if err != OK:
		push_error("Could not save %s (%d)" % [path, err])
	res.take_over_path(path)


var _mat_count := 0


func _save_material(mat: Material) -> void:
	if mat.resource_path != "":
		return
	if mat is ShaderMaterial and (mat as ShaderMaterial).shader and (mat as ShaderMaterial).shader.resource_path == "":
		var sh := (mat as ShaderMaterial).shader
		var sname := "shader_%d" % _mat_count
		var code := sh.code
		if code.contains("shader_type sky"):
			sname = "sky"
		elif code.contains("grass_a"):
			sname = "terrain"
		elif code.contains("shore"):
			sname = "water"
		elif code.contains("tip_col"):
			sname = "grass"
		elif code.contains("leaf"):
			sname = "foliage"
		var sp := "res://assets/shaders/%s.gdshader" % sname
		if FileAccess.file_exists(sp):
			sp = "res://assets/shaders/%s_%d.gdshader" % [sname, _mat_count]
		ResourceSaver.save(sh, sp)
		sh.take_over_path(sp)
	_mat_count += 1
	var path := "res://assets/materials/material_%02d.tres" % _mat_count
	ResourceSaver.save(mat, path)
	mat.take_over_path(path)


func _own(n: Node, owner_node: Node) -> void:
	for c in n.get_children():
		c.owner = owner_node
		if c.scene_file_path == "":
			_own(c, owner_node)


func _add(parent: Node, n: Node, node_name: String) -> Node:
	n.name = node_name
	parent.add_child(n)
	return n


func _pack(root: Node, path: String) -> void:
	_own(root, root)
	var ps := PackedScene.new()
	var err := ps.pack(root)
	if err != OK:
		push_error("pack failed " + path)
	err = ResourceSaver.save(ps, path)
	if err != OK:
		push_error("save failed " + path)
	print("saved ", path)


func _connect(from: Node, sig: String, to: Node, method: String) -> void:
	from.connect(sig, Callable(to, method), Object.CONNECT_PERSIST)


func _sound3d(parent: Node, node_name: String, file: String, volume := 0.0) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = load(AUDIO + file)
	p.volume_db = volume
	p.unit_size = 12.0
	_add(parent, p, node_name)
	return p


func _sound(parent: Node, node_name: String, file: String, volume := 0.0, autoplay := false) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = load(AUDIO + file)
	p.volume_db = volume
	p.autoplay = autoplay
	_add(parent, p, node_name)
	return p


func _timer(parent: Node, node_name: String, wait: float) -> Timer:
	var t := Timer.new()
	t.wait_time = wait
	t.one_shot = true
	_add(parent, t, node_name)
	return t


func _area(parent: Node, node_name: String, radius: float, pos: Vector3, mask: int) -> Area3D:
	var a := Area3D.new()
	a.collision_layer = 0
	a.collision_mask = mask
	a.monitorable = false
	a.position = pos
	_add(parent, a, node_name)
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	var cs := CollisionShape3D.new()
	cs.shape = sphere
	_add(a, cs, "CollisionShape3D")
	return a


func _hide_extras(instance: Node) -> void:
	# Blender exports a camera and a light inside the FBX: they are switched off.
	for c in instance.get_children():
		if c is Light3D:
			(c as Light3D).visible = false
		if c is Camera3D:
			(c as Camera3D).current = false
			(c as Camera3D).visible = false


# ------------------------------------------------------------------ input map
func _key(code: int) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	return e


func _joy_button(b: int) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = b
	return e


func _joy_axis(axis: int, value: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = value
	return e


func _input_map() -> void:
	var actions := {
		"move_left": [_key(KEY_A), _key(KEY_LEFT), _joy_axis(JOY_AXIS_LEFT_X, -1.0)],
		"move_right": [_key(KEY_D), _key(KEY_RIGHT), _joy_axis(JOY_AXIS_LEFT_X, 1.0)],
		"move_forward": [_key(KEY_W), _key(KEY_UP), _joy_axis(JOY_AXIS_LEFT_Y, -1.0)],
		"move_back": [_key(KEY_S), _key(KEY_DOWN), _joy_axis(JOY_AXIS_LEFT_Y, 1.0)],
		"look_left": [_joy_axis(JOY_AXIS_RIGHT_X, -1.0)],
		"look_right": [_joy_axis(JOY_AXIS_RIGHT_X, 1.0)],
		"look_up": [_joy_axis(JOY_AXIS_RIGHT_Y, -1.0)],
		"look_down": [_joy_axis(JOY_AXIS_RIGHT_Y, 1.0)],
		"sprint": [_key(KEY_SHIFT), _joy_button(JOY_BUTTON_LEFT_SHOULDER)],
		"jump": [_key(KEY_SPACE), _joy_button(JOY_BUTTON_A)],
		"pause": [_key(KEY_ESCAPE), _joy_button(JOY_BUTTON_START)],
		"toggle_debug": [_key(KEY_F1), _joy_button(JOY_BUTTON_BACK)],
	}
	for a in actions:
		ProjectSettings.set_setting("input/" + a, {"deadzone": 0.25, "events": actions[a]})
	ProjectSettings.save()


# ------------------------------------------------------------------ Luffy
func _build_luffy() -> void:
	# The CharacterModel helper loads the Mixamo files, fixes the scale, retargets the
	# animations and removes root motion. The result is saved as an AnimationLibrary resource.
	var helper := CharacterModel.new()
	helper.setup("luffy", 1.75)
	var helper_model := helper.get_child(0) as Node3D
	var lib := AnimationLibrary.new()
	var src: AnimationLibrary = helper.anim_player.get_animation_library("team")
	for an in src.get_animation_list():
		lib.add_animation(an, src.get_animation(an).duplicate(true))
	_save(lib, "res://assets/animations/luffy_animations.res")
	print("Luffy animations: ", lib.get_animation_list())

	var root := Player.new()
	root.name = "Luffy"
	root.collision_layer = 2
	root.collision_mask = 1
	root.floor_snap_length = 0.4
	root.floor_max_angle = deg_to_rad(50)
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.75
	var cs := CollisionShape3D.new()
	cs.shape = cap
	cs.position.y = 0.875
	_add(root, cs, "CollisionShape3D")
	var model := (load("res://assets/models/characters/luffy/luffy.fbx") as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Node3D
	model.scale = helper_model.scale
	model.position = helper_model.position
	_add(root, model, "Model")
	var ap := AnimationPlayer.new()
	_add(root, ap, "AnimationPlayer")
	ap.root_node = NodePath("../Model")
	ap.add_animation_library("luffy", lib)
	ap.autoplay = "luffy/idle"
	var pivot := Node3D.new()
	pivot.position.y = 1.6
	_add(root, pivot, "CameraPivot")
	var arm := SpringArm3D.new()
	arm.spring_length = 4.8
	arm.collision_mask = 1
	arm.margin = 0.25
	var sh := SphereShape3D.new()
	sh.radius = 0.25
	arm.shape = sh
	arm.position.x = 0.5
	arm.rotation.x = -0.22
	_add(pivot, arm, "SpringArm3D")
	var cam := Camera3D.new()
	cam.fov = 68.0
	cam.far = 600.0
	cam.current = true
	_add(arm, cam, "Camera3D")
	_sound3d(root, "HurtSound", "hurt.wav")
	_sound3d(root, "JumpSound", "splash.wav", -14.0)
	_timer(root, "InvulnerabilityTimer", 1.2)
	_timer(root, "HurtTimer", 0.45)
	_pack(root, "res://scenes/player/luffy.tscn")
	helper.free()


# ------------------------------------------------------------------ Buggy
func _build_buggy() -> void:
	var target_height := 2.1
	var root := BuggyBoss.new()
	root.name = "Buggy"
	root.collision_layer = 4
	root.collision_mask = 1
	root.floor_snap_length = 0.4
	var cap := CapsuleShape3D.new()
	cap.radius = 0.45
	cap.height = target_height
	var cs := CollisionShape3D.new()
	cs.shape = cap
	cs.position.y = target_height / 2.0
	_add(root, cs, "CollisionShape3D")
	var model_root := Node3D.new()
	_add(root, model_root, "Model")
	var inst := (load("res://assets/models/characters/buggy/buggy.fbx") as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Node3D
	_add(model_root, inst, "BuggyModel")
	var meshes := []
	for c in inst.get_children():
		if c is MeshInstance3D:
			meshes.append(c)
	var box := AABB()
	for i in meshes.size():
		var mi := meshes[i] as MeshInstance3D
		var b := mi.transform * mi.mesh.get_aabb()
		box = b if i == 0 else box.merge(b)
	var k := target_height / box.size.y
	inst.scale = Vector3.ONE * k
	inst.position.y = -box.position.y * k
	# hands and feet are separate meshes: find them by size and position
	var parts := {}
	for mi in meshes:
		var b2 := (mi as MeshInstance3D).transform * (mi as MeshInstance3D).mesh.get_aabb()
		var c2 := b2.get_center()
		var rel_y := (c2.y - box.position.y) / box.size.y
		if b2.size.y > box.size.y * 0.25:
			continue
		var left := c2.x > box.get_center().x  # the model faces +Z, so its left side is +X
		if rel_y < 0.15:
			parts["foot_l" if left else "foot_r"] = mi
		elif rel_y > 0.3 and rel_y < 0.65 and absf(c2.x - box.get_center().x) > box.size.x * 0.2:
			parts["hand_l" if left else "hand_r"] = mi
	print("Buggy parts: ", parts.keys())
	var ap := AnimationPlayer.new()
	_add(root, ap, "AnimationPlayer")
	ap.root_node = NodePath("..")
	ap.add_animation_library("buggy", _buggy_animations(parts, k))
	ap.autoplay = "buggy/idle"
	# areas and timers used by the AI
	var detection := _area(root, "DetectionArea", 10.0, Vector3(0, 1, 0), 2)
	var chase_limit := _area(root, "ChaseLimitArea", 16.0, Vector3(0, 1, 0), 2)
	var attack := _area(root, "AttackArea", 2.4, Vector3(0, 1, 0), 2)
	var hitbox := _area(root, "PunchHitbox", 1.0, Vector3(0, 1.2, 1.8), 2)
	var pause_timer := _timer(root, "PatrolPauseTimer", 1.2)
	var lose_timer := _timer(root, "LoseTimer", 1.2)
	_timer(root, "AttackCooldown", 1.3)
	var label := Label3D.new()
	label.font_size = 56
	label.pixel_size = 0.006
	label.outline_size = 12
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position.y = target_height + 0.55
	label.text = "Patrullando"
	_add(root, label, "StateLabel")
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 9.88
	tm.outer_radius = 10.0
	tm.rings = 64
	tm.ring_segments = 3
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rm.albedo_color = Color(1, 0.85, 0.2, 0.55)
	tm.material = rm
	ring.mesh = tm
	ring.scale = Vector3(1, 0.05, 1)
	ring.position.y = 0.15
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_add(root, ring, "DetectionRing")
	_sound3d(root, "RoarSound", "boss_roar.wav", -4.0)
	_sound3d(root, "SwingSound", "stretch.wav")
	_sound3d(root, "PunchSound", "punch.wav")
	_connect(detection, "body_entered", root, "_on_detection_area_body_entered")
	_connect(chase_limit, "body_exited", root, "_on_chase_limit_area_body_exited")
	_connect(chase_limit, "body_entered", root, "_on_chase_limit_area_body_entered")
	_connect(attack, "body_entered", root, "_on_attack_area_body_entered")
	_connect(attack, "body_exited", root, "_on_attack_area_body_exited")
	_connect(pause_timer, "timeout", root, "_on_patrol_pause_timer_timeout")
	_connect(lose_timer, "timeout", root, "_on_lose_timer_timeout")
	_connect(ap, "animation_finished", root, "_on_animation_player_animation_finished")
	_pack(root, "res://scenes/enemies/buggy.tscn")
	root.free()


## Buggy has no skeleton: his animations move the model parts (hands, feet and body).
func _buggy_animations(parts: Dictionary, k: float) -> AnimationLibrary:
	var lib := AnimationLibrary.new()
	var base := {}
	var center := {}
	var path := {}
	for p in parts:
		var mi := parts[p] as MeshInstance3D
		base[p] = mi.position
		center[p] = mi.transform * mi.mesh.get_aabb().get_center()
		path[p] = "Model/BuggyModel/" + str(mi.name)
	var pos := func(p: String, offset_m: Vector3, grow := 1.0) -> Vector3:
		return base[p] + offset_m / k + (center[p] - base[p]) * (1.0 - grow)
	var scl := func(p: String, grow := 1.0) -> Vector3:
		return (parts[p] as Node3D).scale * grow

	for spec in [["idle", 2.0, 0.0, 0.0, 0.015], ["walk", 0.9, 0.14, 0.12, 0.05], ["run", 0.55, 0.2, 0.16, 0.09]]:
		var a := Animation.new()
		var length: float = spec[1]
		var swing: float = spec[2]
		var lift: float = spec[3]
		var bob: float = spec[4]
		a.length = length
		a.loop_mode = Animation.LOOP_LINEAR
		var body_pos := a.add_track(Animation.TYPE_VALUE)
		a.track_set_path(body_pos, "Model:position")
		var body_rot := a.add_track(Animation.TYPE_VALUE)
		a.track_set_path(body_rot, "Model:rotation")
		var tracks := {}
		for p in parts:
			var t := a.add_track(Animation.TYPE_VALUE)
			a.track_set_path(t, str(path[p]) + ":position")
			tracks[p] = t
		var lean := 0.18 if spec[0] == "run" else 0.0
		for i in 9:
			var time := length * i / 8.0
			var ph := TAU * i / 8.0
			var step := sin(ph)
			a.track_insert_key(body_pos, time, Vector3(0, absf(step) * bob if swing > 0.0 else (sin(ph) * 0.5 + 0.5) * bob, 0))
			a.track_insert_key(body_rot, time, Vector3(lean, 0, sin(ph * 0.5) * 0.03 if swing > 0.0 else sin(ph) * 0.02))
			for p in parts:
				var off := Vector3.ZERO
				match p:
					"foot_r":
						off = Vector3(0, maxf(0.0, step) * lift, step * swing * 1.3)
					"foot_l":
						off = Vector3(0, maxf(0.0, -step) * lift, -step * swing * 1.3)
					"hand_r":
						off = Vector3(0, 0, -step * swing if swing > 0.0 else sin(ph) * 0.02)
					"hand_l":
						off = Vector3(0, 0, step * swing if swing > 0.0 else -sin(ph) * 0.02)
				a.track_insert_key(tracks[p], time, pos.call(p, off))
		lib.add_animation(spec[0], a)

	# punch: wind-up, the right hand flies forward (and grows), hits, comes back
	var punch := Animation.new()
	punch.length = 1.0
	var reach := 2.2
	var hp := punch.add_track(Animation.TYPE_VALUE)
	punch.track_set_path(hp, str(path["hand_r"]) + ":position")
	var hs := punch.add_track(Animation.TYPE_VALUE)
	punch.track_set_path(hs, str(path["hand_r"]) + ":scale")
	var br := punch.add_track(Animation.TYPE_VALUE)
	punch.track_set_path(br, "Model:rotation")
	var bp := punch.add_track(Animation.TYPE_VALUE)
	punch.track_set_path(bp, "Model:position")
	var keys := [[0.0, Vector3.ZERO, 1.0, -0.0], [0.4, Vector3(0, 0.15, -0.35), 1.0, -0.12], [0.6, Vector3(0.2, 0.2, reach), 1.7, 0.22],
		[0.7, Vector3(0.2, 0.2, reach), 1.7, 0.22], [1.0, Vector3.ZERO, 1.0, 0.0]]
	for kf in keys:
		punch.track_insert_key(hp, kf[0], pos.call("hand_r", kf[1], kf[2]))
		punch.track_insert_key(hs, kf[0], scl.call("hand_r", kf[2]))
		punch.track_insert_key(br, kf[0], Vector3(kf[3], 0, 0))
		punch.track_insert_key(bp, kf[0], Vector3.ZERO)
	var mt := punch.add_track(Animation.TYPE_METHOD)
	punch.track_set_path(mt, ".")
	punch.track_insert_key(mt, 0.4, {"method": "_on_punch_start", "args": []})
	punch.track_insert_key(mt, 0.62, {"method": "_on_punch_impact", "args": []})
	lib.add_animation("punch", punch)
	_save(lib, "res://assets/animations/buggy_animations.res")
	return lib


# ------------------------------------------------------------------ meat (collectible)
func _build_meat() -> void:
	var root := Collectible.new()
	root.name = "Meat"
	root.collision_layer = 8
	root.collision_mask = 2
	root.monitorable = false
	var sphere := SphereShape3D.new()
	sphere.radius = 0.9
	var cs := CollisionShape3D.new()
	cs.shape = sphere
	cs.position.y = 0.6
	_add(root, cs, "CollisionShape3D")
	var visual := Node3D.new()
	visual.position.y = 0.6
	_add(root, visual, "Visual")
	var meat_mat := StandardMaterial3D.new()
	meat_mat.albedo_color = Color(0.55, 0.22, 0.12)
	meat_mat.roughness = 0.55
	var bone_mat := StandardMaterial3D.new()
	bone_mat.albedo_color = Color(0.95, 0.92, 0.85)
	var meat := MeshInstance3D.new()
	var mm := CapsuleMesh.new()
	mm.radius = 0.28
	mm.height = 0.8
	mm.material = meat_mat
	meat.mesh = mm
	meat.rotation.z = PI / 2.0
	_add(visual, meat, "MeatMesh")
	var bone := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.06
	bm.bottom_radius = 0.06
	bm.height = 1.3
	bm.material = bone_mat
	bone.mesh = bm
	bone.rotation.z = PI / 2.0
	_add(visual, bone, "BoneMesh")
	for side in [-1, 1]:
		var end := MeshInstance3D.new()
		var em := SphereMesh.new()
		em.radius = 0.11
		em.height = 0.22
		em.material = bone_mat
		end.mesh = em
		end.position.x = 0.66 * side
		_add(visual, end, "BoneEndLeft" if side < 0 else "BoneEndRight")
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.8, 0.4)
	light.light_energy = 1.5
	light.omni_range = 3.0
	_add(visual, light, "Glow")
	var ap := AnimationPlayer.new()
	_add(root, ap, "AnimationPlayer")
	var lib := AnimationLibrary.new()
	var a := Animation.new()
	a.length = 2.0
	a.loop_mode = Animation.LOOP_LINEAR
	var tp := a.add_track(Animation.TYPE_VALUE)
	a.track_set_path(tp, "Visual:position")
	a.track_insert_key(tp, 0.0, Vector3(0, 0.6, 0))
	a.track_insert_key(tp, 1.0, Vector3(0, 0.9, 0))
	a.track_insert_key(tp, 2.0, Vector3(0, 0.6, 0))
	var tr := a.add_track(Animation.TYPE_VALUE)
	a.track_set_path(tr, "Visual:rotation")
	a.track_insert_key(tr, 0.0, Vector3(0, 0, 0))
	a.track_insert_key(tr, 2.0, Vector3(0, TAU, 0))
	lib.add_animation("float", a)
	ap.add_animation_library("", lib)
	ap.autoplay = "float"
	var snd := _sound3d(root, "PickupSound", "pickup.wav")
	_connect(root, "body_entered", root, "_on_body_entered")
	_connect(snd, "finished", root, "_on_pickup_sound_finished")
	_pack(root, "res://scenes/items/meat.tscn")
	root.free()


# ------------------------------------------------------------------ UI
func _label(parent: Node, node_name: String, text: String, size: int, color: Color = UITheme.TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	_add(parent, l, node_name)
	return l


func _place(c: Control, preset: int, l: float, t: float, r: float, b: float) -> void:
	c.set_anchors_preset(preset)
	c.offset_left = l
	c.offset_top = t
	c.offset_right = r
	c.offset_bottom = b


func _button(parent: Node, node_name: String, text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(260, 0)
	_add(parent, b, node_name)
	return b


func _build_hud() -> void:
	var root := HUD.new()
	root.name = "HUD"
	var ui := Control.new()
	ui.theme = theme
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_add(root, ui, "Root")
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UITheme.box(Color(0.05, 0.07, 0.12, 0.75), Color(0.93, 0.78, 0.42, 0.6), 1, 6, 10))
	_add(ui, panel, "PlayerPanel")
	_place(panel, Control.PRESET_TOP_LEFT, 16, 16, 340, 86)
	var v := VBoxContainer.new()
	_add(panel, v, "VBox")
	var row := HBoxContainer.new()
	_add(v, row, "Row")
	_label(row, "NameLabel", "Luffy", 22, UITheme.GOLD)
	var hl := _label(row, "HealthLabel", "100 / 100", 18)
	hl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var bar := UITheme.bar(Color(0.3, 0.85, 0.4), 300, 16)
	bar.value = 100
	_add(v, bar, "HealthBar")
	var item_panel := PanelContainer.new()
	item_panel.add_theme_stylebox_override("panel", UITheme.box(Color(0.05, 0.07, 0.12, 0.75), Color(0.93, 0.78, 0.42, 0.6), 1, 6, 10))
	_add(ui, item_panel, "ItemPanel")
	_place(item_panel, Control.PRESET_TOP_RIGHT, -230, 16, -16, 64)
	_label(item_panel, "ItemLabel", "Carne: 0 / 5", 22, UITheme.GOLD)
	var boss := VBoxContainer.new()
	_add(ui, boss, "BossBox")
	_place(boss, Control.PRESET_CENTER_TOP, -260, 16, 260, 90)
	var bn := _label(boss, "BossName", "Buggy el Payaso", 26, Color(1, 0.6, 0.45))
	bn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var bs := _label(boss, "BossState", "IA: Patrullando", 18, UITheme.DIM)
	bs.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var msg := _label(ui, "Message", "", 40, UITheme.GOLD)
	_place(msg, Control.PRESET_CENTER_TOP, -500, 100, 500, 160)
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.visible = false
	var ctl := _label(ui, "ControlsHint", "WASD mover  ·  Shift correr  ·  Espacio saltar  ·  Mouse cámara  ·  F1 ver IA  ·  Esc pausa", 16, UITheme.DIM)
	_place(ctl, Control.PRESET_CENTER_BOTTOM, -500, -40, 500, -12)
	ctl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var mt := _timer(root, "MessageTimer", 2.0)
	_connect(mt, "timeout", root, "_on_message_timer_timeout")
	_pack(root, "res://scenes/ui/hud.tscn")
	root.free()


func _center_panel(root: Node, w: float, h: float) -> VBoxContainer:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	_add(root, dim, "Dim")
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.theme = theme
	_add(root, panel, "Panel")
	_place(panel, Control.PRESET_CENTER, -w / 2.0, -h / 2.0, w / 2.0, h / 2.0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	_add(panel, v, "VBox")
	return v


func _build_pause_menu() -> void:
	var root := PauseMenu.new()
	root.name = "PauseMenu"
	root.layer = 5
	root.visible = false
	root.process_mode = Node.PROCESS_MODE_ALWAYS
	var v := _center_panel(root, 340, 270)
	var t := _label(v, "Title", "Pausa", 30, UITheme.GOLD)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_connect(_button(v, "ContinueButton", "Continuar"), "pressed", root, "_on_continue_button_pressed")
	_connect(_button(v, "MenuButton", "Volver al menú"), "pressed", root, "_on_menu_button_pressed")
	_connect(_button(v, "QuitButton", "Salir del juego"), "pressed", root, "_on_quit_button_pressed")
	_pack(root, "res://scenes/ui/pause_menu.tscn")
	root.free()


func _build_end_screen() -> void:
	var root := EndScreen.new()
	root.name = "EndScreen"
	root.layer = 6
	root.visible = false
	root.process_mode = Node.PROCESS_MODE_ALWAYS
	var v := _center_panel(root, 560, 320)
	var t := _label(v, "Title", "¡Lo lograste!", 40, UITheme.GOLD)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var d := _label(v, "Detail", "", 20)
	d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_connect(_button(v, "RetryButton", "Jugar de nuevo"), "pressed", root, "_on_retry_button_pressed")
	_connect(_button(v, "MenuButton", "Menú principal"), "pressed", root, "_on_menu_button_pressed")
	_pack(root, "res://scenes/ui/end_screen.tscn")
	root.free()


func _build_main_menu() -> void:
	var root := Control.new()
	root.set_script(load("res://scripts/main_menu.gd"))
	root.name = "MainMenu"
	root.theme = theme
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := TextureRect.new()
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.35, 0.55, 0.56, 1.0])
	grad.colors = PackedColorArray([Color(0.16, 0.13, 0.3), Color(0.52, 0.24, 0.38), Color(0.95, 0.58, 0.35), Color(0.08, 0.2, 0.38), Color(0.05, 0.13, 0.27)])
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	gt.width = 64
	gt.height = 256
	bg.texture = gt
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	_add(root, bg, "Background")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var t1 := _label(root, "TitleSmall", "RUMBO AL", 30)
	_place(t1, Control.PRESET_CENTER_TOP, -300, 70, 300, 110)
	t1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var t2 := _label(root, "Title", "ONE PIECE", 84, UITheme.GOLD)
	_place(t2, Control.PRESET_CENTER_TOP, -400, 100, 400, 210)
	t2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var t3 := _label(root, "Subtitle", "BETA · Primera presentación", 20, UITheme.DIM)
	_place(t3, Control.PRESET_CENTER_TOP, -300, 205, 300, 235)
	t3.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var menu := PanelContainer.new()
	_add(root, menu, "MenuPanel")
	_place(menu, Control.PRESET_CENTER, -150, 10, 150, 200)
	var mv := VBoxContainer.new()
	mv.add_theme_constant_override("separation", 10)
	_add(menu, mv, "VBox")
	_connect(_button(mv, "PlayButton", "Jugar"), "pressed", root, "_on_play_button_pressed")
	_connect(_button(mv, "ControlsButton", "Controles"), "pressed", root, "_on_controls_button_pressed")
	_connect(_button(mv, "QuitButton", "Salir"), "pressed", root, "_on_quit_button_pressed")
	var controls := PanelContainer.new()
	controls.visible = false
	_add(root, controls, "ControlsPanel")
	_place(controls, Control.PRESET_CENTER, -280, -10, 280, 330)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 10)
	_add(controls, cv, "VBox")
	_label(cv, "Title", "Controles", 26, UITheme.GOLD)
	_label(cv, "Text", "Objetivo: recoge toda la carne sin que Buggy te atrape.\n\nWASD / flechas: mover\nShift: correr\nEspacio: saltar\nMouse: mover la cámara\nF1: mostrar u ocultar la IA de Buggy\nEsc: pausa", 18)
	_connect(_button(cv, "BackButton", "Volver"), "pressed", root, "_on_back_button_pressed")
	var music := _sound(root, "MenuMusic", "music_menu.wav", -8.0, true)
	_connect(music, "finished", music, "play")
	_sound(root, "ClickSound", "select.wav")
	_pack(root, "res://scenes/main_menu.tscn")
	root.free()


# ------------------------------------------------------------------ game scene
func _build_game() -> void:
	var root := Node3D.new()
	root.set_script(load("res://scripts/game_world.gd"))
	root.name = "Game"
	# environment
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky.sky_material = Mat.sky()
	_save_material(sky.sky_material)
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 6.0
	env.ssao_enabled = true
	env.glow_enabled = true
	env.glow_intensity = 0.3
	env.fog_enabled = true
	env.fog_light_color = Color(0.7, 0.8, 0.9)
	env.fog_density = 0.002
	env.fog_aerial_perspective = 0.4
	_save(env, "res://assets/generated/environment.tres")
	var we := WorldEnvironment.new()
	we.environment = env
	_add(root, we, "WorldEnvironment")
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-40), deg_to_rad(-35), 0)
	sun.light_energy = 1.5
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 90.0
	_add(root, sun, "Sun")
	# island
	var builder := IslandBuilder.new(root, _save)
	builder.build(root)
	# markers
	var start := Marker3D.new()
	start.position = builder.ground(IslandBuilder.PLAYER_START)
	_add(root, start, "PlayerStart")
	var patrol := Node3D.new()
	_add(root, patrol, "BuggyPatrol")
	var left := Marker3D.new()
	left.position = builder.ground(IslandBuilder.PATROL_LEFT)
	_add(patrol, left, "PatrolLeft")
	var right := Marker3D.new()
	right.position = builder.ground(IslandBuilder.PATROL_RIGHT)
	_add(patrol, right, "PatrolRight")
	# UI first, so it is ready before the characters emit their first signals
	var hud := (load("res://scenes/ui/hud.tscn") as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	_add(root, hud, "HUD")
	var pause := (load("res://scenes/ui/pause_menu.tscn") as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	_add(root, pause, "PauseMenu")
	var end_screen := (load("res://scenes/ui/end_screen.tscn") as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	_add(root, end_screen, "EndScreen")
	# characters
	var luffy := (load("res://scenes/player/luffy.tscn") as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Node3D
	luffy.position = start.position + Vector3(0, 0.2, 0)
	_add(root, luffy, "Luffy")
	var buggy := (load("res://scenes/enemies/buggy.tscn") as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Node3D
	buggy.position = left.position + Vector3(0, 0.2, 0)
	_add(root, buggy, "Buggy")
	buggy.set("patrol_left", left)
	buggy.set("patrol_right", right)
	buggy.set("target", luffy)
	# collectibles: some easy, some close to Buggy's patrol line
	var items := Node3D.new()
	_add(root, items, "Collectibles")
	var c := IslandBuilder.CENTER
	var spots := [Vector3(c - 8, 0, c - 15.5), Vector3(c + 9, 0, c - 7.5), Vector3(c + 1, 0, c - 21), Vector3(c - 22, 0, c - 2), Vector3(c + 21, 0, c + 6)]
	var meat_scene := load("res://scenes/items/meat.tscn") as PackedScene
	for i in spots.size():
		var m := meat_scene.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Node3D
		m.position = builder.ground(spots[i])
		_add(items, m, "Meat%d" % (i + 1))
		_connect(m, "collected", root, "_on_item_collected")
	# audio and timers
	var explore := _sound(root, "ExploreMusic", "music_island.wav", -8.0, true)
	_connect(explore, "finished", explore, "play")
	var chase := _sound(root, "ChaseMusic", "music_combat.wav", -40.0)
	_connect(chase, "finished", chase, "play")
	_sound(root, "VictorySound", "victory.wav")
	_sound(root, "DefeatSound", "defeat.wav")
	var defeat_timer := _timer(root, "DefeatTimer", 1.5)
	# signal connections
	_connect(luffy, "health_changed", hud, "set_health")
	_connect(luffy, "died", root, "_on_player_died")
	_connect(buggy, "state_changed", root, "_on_buggy_state_changed")
	_connect(defeat_timer, "timeout", root, "_on_defeat_timer_timeout")
	# owners: the instanced scenes keep their own nodes
	for n in [hud, pause, end_screen, luffy, buggy]:
		n.owner = root
	for m2 in items.get_children():
		m2.owner = root
	_pack(root, "res://scenes/game.tscn")
	root.free()
