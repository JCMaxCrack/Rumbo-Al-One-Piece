extends Node
## Builds the terrain, the minimap and the scenes of the islands Villa Syrup and Whisky Peak.
## It must run as a scene (so the autoloads exist):
##   godot --headless --path . res://tools/build_islands.tscn -- assets   (terrain, water, minimap, environment)
##   godot --headless --path . --import                                  (imports the new minimap PNGs)
##   godot --headless --path . res://tools/build_islands.tscn -- scenes   (scenes/islands/*.tscn)
## The music comes from tools/make_island_music.py. Everything is deterministic: the layout
## (tools/island_layout.gd) is rebuilt in both stages, so the scenes match the saved height maps.

const ISLANDS := ["villa_syrup", "whisky_peak"]
const SCENES := {"villa_syrup": "res://scenes/islands/villa_syrup.tscn", "whisky_peak": "res://scenes/islands/whisky_peak.tscn"}
const SCRIPTS := {"villa_syrup": "res://scripts/syrup_island.gd", "whisky_peak": "res://scripts/whisky_island.gd"}
const ROOT_NAMES := {"villa_syrup": "VillaSyrup", "whisky_peak": "WhiskyPeak"}

var _root: Node
var _layout: IslandLayout
var _mats := {}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	var stage := ""
	for a in OS.get_cmdline_user_args():
		stage = a
	for id in ISLANDS:
		match stage:
			"assets":
				_build_assets(id)
			"scenes":
				_build_scene(id)
	if stage == "":
		push_error("usage: -- assets | scenes")
	get_tree().quit()


# =================================================================== stage 1: assets
func _path(kind: String, id: String) -> String:
	match kind:
		"mesh": return "res://assets/generated/%s_terrain_mesh.res" % id
		"shape": return "res://assets/generated/%s_terrain_shape.res" % id
		"material": return "res://assets/generated/%s_terrain_material.tres" % id
		"shore": return "res://assets/generated/%s_shore_mask.res" % id
		"water": return "res://assets/generated/%s_water_material.tres" % id
		"env": return "res://assets/generated/%s_environment.tres" % id
		"minimap": return "res://assets/ui/minimap_%s.png" % id
		"music": return "res://assets/audio/music_%s.wav" % id
	return ""


func _build_assets(id: String) -> void:
	var L := IslandLayout.new(id)
	L.build()
	var N := IslandLayout.N
	# collision
	var shape := HeightMapShape3D.new()
	shape.map_width = N
	shape.map_depth = N
	# the collision node is scaled x2 (also in height), like the one of the first island
	var half := PackedFloat32Array()
	half.resize(L.heights.size())
	for k in L.heights.size():
		half[k] = L.heights[k] * 0.5
	shape.map_data = half
	_save(shape, _path("shape", id))
	# terrain material
	var tm := ShaderMaterial.new()
	tm.shader = load("res://assets/shaders/terrain_island.gdshader")
	if id == "villa_syrup":
		tm.set_shader_parameter("rock_height_start", 20.0)
		tm.set_shader_parameter("rock_height_end", 30.0)
		tm.set_shader_parameter("snow_height_start", 99.0)
		tm.set_shader_parameter("snow_height_end", 100.0)
		tm.set_shader_parameter("grass_a", Color(0.12, 0.24, 0.1))
		tm.set_shader_parameter("grass_b", Color(0.24, 0.34, 0.14))
	else:
		tm.set_shader_parameter("rock_height_start", 24.0)
		tm.set_shader_parameter("rock_height_end", 34.0)
		tm.set_shader_parameter("snow_height_start", 99.0)
		tm.set_shader_parameter("snow_height_end", 100.0)
		tm.set_shader_parameter("grass_a", Color(0.62, 0.48, 0.28))
		tm.set_shader_parameter("grass_b", Color(0.74, 0.58, 0.34))
		tm.set_shader_parameter("dry", Color(0.82, 0.66, 0.42))
		tm.set_shader_parameter("sand", Color(0.9, 0.8, 0.6))
		tm.set_shader_parameter("dirt", Color(0.7, 0.5, 0.32))
		tm.set_shader_parameter("paving", Color(0.62, 0.52, 0.42))
		tm.set_shader_parameter("rock_a", Color(0.5, 0.28, 0.18))
		tm.set_shader_parameter("rock_b", Color(0.78, 0.5, 0.34))
		tm.set_shader_parameter("dry_amount", 0.9)
	_save(tm, _path("material", id))
	# terrain mesh (same grid as the collision)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	verts.resize(N * N)
	normals.resize(N * N)
	colors.resize(N * N)
	for j in N:
		for i in N:
			var h := L.heights[j * N + i]
			var hl := L.heights[j * N + maxi(i - 1, 0)]
			var hr := L.heights[j * N + mini(i + 1, N - 1)]
			var hu := L.heights[maxi(j - 1, 0) * N + i]
			var hd := L.heights[mini(j + 1, N - 1) * N + i]
			var p := Vector2(i * IslandLayout.STEP, j * IslandLayout.STEP)
			verts[j * N + i] = Vector3(p.x, h, p.y)
			normals[j * N + i] = Vector3(hl - hr, 2.0 * IslandLayout.STEP, hu - hd).normalized()
			var sand := clampf((1.95 - h) / 0.8, 0.0, 1.0)
			colors[j * N + i] = Color(sand, L.path_mask(p), L.pave_mask(p), 0.0)
	var idx := PackedInt32Array()
	for j in N - 1:
		for i in N - 1:
			var a := j * N + i
			var b := a + 1
			var c := a + N
			var d := c + 1
			idx.append_array([a, b, c, b, d, c])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, load(_path("material", id)))
	_save(mesh, _path("mesh", id))
	# water: foam and shallow colour near the coast
	var shore := Image.create(512, 512, false, Image.FORMAT_L8)
	for y in 512:
		for x in 512:
			var h := L.ground((x + 0.5) / 512.0 * IslandLayout.WORLD, (y + 0.5) / 512.0 * IslandLayout.WORLD)
			var s := clampf((h + 3.5) / 3.4, 0.0, 1.0)
			s = s * s * (3.0 - 2.0 * s)
			shore.set_pixel(x, y, Color(s, s, s))
	var shore_tex := ImageTexture.create_from_image(shore)
	_save(shore_tex, _path("shore", id))
	var wm := (load("res://assets/materials/material_03.tres") as ShaderMaterial).duplicate() as ShaderMaterial
	wm.set_shader_parameter("shore", load(_path("shore", id)))
	wm.set_shader_parameter("map_size", Vector2(IslandLayout.WORLD, IslandLayout.WORLD))
	if id == "whisky_peak":
		wm.set_shader_parameter("deep", Color(0.03, 0.2, 0.35))
		wm.set_shader_parameter("shallow", Color(0.22, 0.68, 0.64))
	else:
		wm.set_shader_parameter("deep", Color(0.02, 0.15, 0.26))
		wm.set_shader_parameter("shallow", Color(0.1, 0.45, 0.5))
	_save(wm, _path("water", id))
	# sky and fog
	var env := (load("res://assets/generated/environment.tres") as Environment).duplicate(true) as Environment
	var sky_mat := (load("res://assets/materials/material_01.tres") as ShaderMaterial).duplicate() as ShaderMaterial
	if id == "villa_syrup":
		sky_mat.set_shader_parameter("top", Color(0.26, 0.38, 0.5))
		sky_mat.set_shader_parameter("horizon", Color(0.68, 0.74, 0.76))
		env.fog_light_color = Color(0.64, 0.72, 0.72)
		env.ambient_light_energy = 0.6
	else:
		sky_mat.set_shader_parameter("top", Color(0.2, 0.46, 0.82))
		sky_mat.set_shader_parameter("horizon", Color(0.96, 0.84, 0.64))
		env.fog_light_color = Color(0.93, 0.83, 0.68)
		env.ambient_light_energy = 0.8
	(env.sky as Sky).sky_material = sky_mat
	_save(env, _path("env", id))
	_save_minimap(L, id)
	print("assets of %s done" % id)


func _save(res: Resource, path: String) -> void:
	var err := ResourceSaver.save(res, path)
	if err != OK:
		push_error("could not save %s (%d)" % [path, err])
	else:
		res.take_over_path(path)


func _save_minimap(L: IslandLayout, id: String) -> void:
	var size := 512
	var px := IslandLayout.WORLD / size
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var syrup := id == "villa_syrup"
	for y in size:
		for x in size:
			var wx := (x + 0.5) * px
			var wz := (y + 0.5) * px
			var h := L.ground(wx, wz)
			var col: Color
			if h < 0.0:
				col = Color(0.07, 0.27, 0.45).lerp(Color(0.14, 0.52, 0.62), clampf((h + 3.0) / 3.0, 0.0, 1.0))
			else:
				if h < 1.9:
					col = Color(0.86, 0.79, 0.58)
				elif syrup:
					col = Color(0.26, 0.45, 0.2).lerp(Color(0.5, 0.5, 0.42), clampf((h - 8.0) / 8.0, 0.0, 1.0))
				else:
					col = Color(0.82, 0.64, 0.4).lerp(Color(0.66, 0.4, 0.28), clampf((h - 8.0) / 12.0, 0.0, 1.0))
				var p := Vector2(wx, wz)
				col = col.lerp(Color(0.72, 0.6, 0.42), L.path_mask(p) * 0.9)
				if L.pave_mask(p) > 0.5:
					col = Color(0.58, 0.57, 0.53)
				var shade := L.ground(wx - 2.0, wz - 2.0) - L.ground(wx + 2.0, wz + 2.0)
				col = col * (1.0 + clampf(shade * 0.09, -0.3, 0.3))
			col.a = 1.0
			img.set_pixel(x, y, col)
	for fp in L.footprints:
		var r: Rect2 = fp[0]
		var c: Color = fp[1]
		var x0 := int(r.position.x / px)
		var y0 := int(r.position.y / px)
		var x1 := int(r.end.x / px)
		var y1 := int(r.end.y / px)
		for y in range(y0, y1 + 1):
			for x in range(x0, x1 + 1):
				if x < 0 or y < 0 or x >= size or y >= size:
					continue
				var edge := x == x0 or x == x1 or y == y0 or y == y1
				if edge or c.a >= 1.0 or c.a > 0.0 and (x + y) % 3 == 0:
					img.set_pixel(x, y, Color(c.r, c.g, c.b, 1.0))
				elif c.a >= 0.5:
					pass
	img.save_png(_path("minimap", id))


# =================================================================== stage 2: scenes
func _build_scene(id: String) -> void:
	_layout = IslandLayout.new(id)
	_layout.build()
	_mats = {}
	_rng.seed = 4242 if id == "villa_syrup" else 777
	_root = Node3D.new()
	_root.name = ROOT_NAMES[id]
	_root.set_script(load(SCRIPTS[id]))
	_root.set("island_id", id)
	_root.set("minimap_texture", load(_path("minimap", id)))
	_root.set("world_size", IslandLayout.WORLD)
	_base_nodes(id)
	if id == "villa_syrup":
		_build_syrup()
	else:
		_build_whisky()
	_common_nodes(id)
	# the connections of the instanced pickups come with their own scene: do not save them twice
	for group in ["Collectibles", "Checkpoints"]:
		for n in _root.get_node(group).get_children():
			var cb := Callable(n, "_on_body_entered")
			if n.is_connected("body_entered", cb):
				n.disconnect("body_entered", cb)
	var packed := PackedScene.new()
	var err := packed.pack(_root)
	if err != OK:
		push_error("pack failed %d" % err)
		return
	DirAccess.make_dir_recursive_absolute("res://scenes/islands")
	err = ResourceSaver.save(packed, SCENES[id])
	print("scene %s saved (%d)" % [SCENES[id], err])
	_root.free()


# ------------------------------------------------------------------ helpers
func _add(parent: Node, child: Node, node_name := "") -> Node:
	if node_name != "":
		child.name = node_name
	parent.add_child(child, true)
	child.owner = _root
	return child


func _n3(parent: Node, node_name: String, pos := Vector3.ZERO, yaw := 0.0) -> Node3D:
	var n := Node3D.new()
	_add(parent, n, node_name)
	n.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(yaw)), pos)
	return n


func _inst(path: String, parent: Node, node_name: String, pos: Vector3, yaw := 0.0) -> Node:
	var n := (load(path) as PackedScene).instantiate()
	_add(parent, n, node_name)
	if n is Node3D:
		(n as Node3D).transform = Transform3D(Basis(Vector3.UP, deg_to_rad(yaw)), pos)
	return n


func _m(color: Color, rough := 0.9, emission := 0.0, metallic := 0.0) -> StandardMaterial3D:
	var key := "%s_%s_%s_%s" % [color.to_html(), rough, emission, metallic]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metallic
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission
	_mats[key] = m
	return m


func _body(parent: Node, node_name: String, pos := Vector3.ZERO, yaw := 0.0) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.collision_mask = 0
	_add(parent, b, node_name)
	b.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(yaw)), pos)
	return b


func _mesh(parent: Node, node_name: String, mesh: Mesh, pos: Vector3, material: Material, rot := Vector3.ZERO, shadows := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mesh.set("material", material)
	mi.mesh = mesh
	if not shadows:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_add(parent, mi, node_name)
	mi.transform = Transform3D(Basis.from_euler(rot), pos)
	return mi


func _collider(parent: Node, shape: Shape3D, pos: Vector3, rot := Vector3.ZERO) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	cs.shape = shape
	_add(parent, cs, "Shape")
	cs.transform = Transform3D(Basis.from_euler(rot), pos)
	return cs


## A box with its mesh and (optionally) its collision, under `parent`.
func _box(parent: Node, node_name: String, pos: Vector3, size: Vector3, material: Material, solid := true, rot := Vector3.ZERO) -> void:
	var bm := BoxMesh.new()
	bm.size = size
	_mesh(parent, node_name, bm, pos, material, rot)
	if solid:
		var bs := BoxShape3D.new()
		bs.size = size
		_collider(parent, bs, pos, rot)


func _cyl(parent: Node, node_name: String, pos: Vector3, radius: float, height: float, material: Material, solid := true, rot := Vector3.ZERO, top_radius := -1.0) -> void:
	var cm := CylinderMesh.new()
	cm.top_radius = radius if top_radius < 0.0 else top_radius
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = 14
	cm.rings = 1
	_mesh(parent, node_name, cm, pos, material, rot)
	if solid:
		var cs := CylinderShape3D.new()
		cs.radius = radius
		cs.height = height
		_collider(parent, cs, pos, rot)


func _ground(p: Vector2) -> float:
	return _layout.ground(p.x, p.y)


func _on_ground(p: Vector2, lift := 0.0) -> Vector3:
	return Vector3(p.x, _ground(p) + lift, p.y)


func _light(parent: Node, pos: Vector3, color: Color, energy: float, range_m: float) -> void:
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = range_m
	l.shadow_enabled = false
	l.add_to_group("dynamic_lights", true)
	_add(parent, l, "Light")
	l.position = pos


func _label(parent: Node, text: String, pos: Vector3, size := 0.012, color := Color(1, 1, 1)) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.pixel_size = size
	l.font_size = 64
	l.modulate = color
	l.outline_size = 12
	_add(parent, l, "Label")
	l.position = pos
	return l


# ------------------------------------------------------------------ nodes that every island has
func _base_nodes(id: String) -> void:
	var env := WorldEnvironment.new()
	env.environment = load(_path("env", id))
	_add(_root, env, "WorldEnvironment")
	var sun := DirectionalLight3D.new()
	sun.transform = Transform3D(Basis(Vector3(0.81915206, 0, 0.57357645), Vector3(0.3686878, 0.76604444, -0.52654076), Vector3(-0.43938506, 0.6427876, 0.62750685)), Vector3.ZERO)
	sun.light_color = Color(0.96, 0.95, 0.9) if id == "villa_syrup" else Color(1.0, 0.88, 0.7)
	sun.light_energy = 1.25 if id == "villa_syrup" else 1.7
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 90.0
	_add(_root, sun, "Sun")
	var island := _n3(_root, "Island")
	var terrain := MeshInstance3D.new()
	terrain.mesh = load(_path("mesh", id))
	_add(island, terrain, "Terrain")
	var tb := StaticBody3D.new()
	tb.collision_mask = 0
	_add(island, tb, "TerrainBody")
	var cs := CollisionShape3D.new()
	cs.shape = load(_path("shape", id))
	_add(tb, cs, "CollisionShape3D")
	cs.transform = Transform3D(Basis.from_scale(Vector3(2, 2, 2)), Vector3(200, 0, 200))
	var water := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(2040, 2040)
	pm.subdivide_width = 128
	pm.subdivide_depth = 128
	pm.material = load(_path("water", id))
	water.mesh = pm
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_add(island, water, "Water")
	water.position = Vector3(200, 0, 200)
	# invisible walls at the edge of the map
	var borders := StaticBody3D.new()
	borders.collision_mask = 0
	_add(island, borders, "Borders")
	for w in [[Vector3(-1, 20, 200), Vector3(2, 60, 404)], [Vector3(401, 20, 200), Vector3(2, 60, 404)],
			[Vector3(200, 20, -1), Vector3(404, 60, 2)], [Vector3(200, 20, 401), Vector3(404, 60, 2)]]:
		var bs := BoxShape3D.new()
		bs.size = w[1]
		_collider(borders, bs, w[0])
	_n3(island, "Props")
	_port(island)
	_n3(_root, "Collectibles")
	_n3(_root, "Checkpoints")
	_n3(_root, "MiniEnemies")


func _common_nodes(id: String) -> void:
	var hud := _inst("res://scenes/ui/hud.tscn", _root, "HUD", Vector3.ZERO)
	var touch := _inst("res://scenes/ui/touch_controls.tscn", _root, "TouchControls", Vector3.ZERO)
	var pause := _inst("res://scenes/ui/pause_menu.tscn", _root, "PauseMenu", Vector3.ZERO)
	_inst("res://scenes/ui/end_screen.tscn", _root, "EndScreen", Vector3.ZERO)
	var start := _layout.ground(200, 322) + 0.3
	var luffy := _inst("res://scenes/player/luffy.tscn", _root, "Luffy", Vector3(200, start, 322))
	var explore := AudioStreamPlayer.new()
	explore.stream = load(_path("music", id))
	explore.volume_db = -8.0
	explore.autoplay = true
	_add(_root, explore, "ExploreMusic")
	var chase := AudioStreamPlayer.new()
	chase.stream = load("res://assets/audio/music_combat.wav")
	chase.volume_db = -40.0
	_add(_root, chase, "ChaseMusic")
	var victory := AudioStreamPlayer.new()
	victory.stream = load("res://assets/audio/victory.wav")
	_add(_root, victory, "VictorySound")
	var defeat := AudioStreamPlayer.new()
	defeat.stream = load("res://assets/audio/defeat.wav")
	_add(_root, defeat, "DefeatSound")
	var timer := Timer.new()
	timer.wait_time = 1.5
	timer.one_shot = true
	_add(_root, timer, "DefeatTimer")
	timer.timeout.connect(Callable(_root, "_on_defeat_timer_timeout"), CONNECT_PERSIST)
	explore.finished.connect(Callable(explore, "play"), CONNECT_PERSIST)
	chase.finished.connect(Callable(chase, "play"), CONNECT_PERSIST)
	touch.connect("look_dragged", Callable(luffy, "look"), CONNECT_PERSIST)
	pause.connect("save_requested", Callable(_root, "_on_pause_menu_save_requested"), CONNECT_PERSIST)
	luffy.connect("health_changed", Callable(hud, "set_health"), CONNECT_PERSIST)


## The port is the same in every island: a dock in the south and the Going Merry at its end,
## with a gangplank up to the stern deck, where the helm is.
func _port(island: Node) -> void:
	var wood := _m(Color(0.45, 0.32, 0.2), 0.9)
	var dark := _m(Color(0.3, 0.2, 0.13), 0.9)
	var dock := _body(island, "Dock")
	var length := IslandLayout.DOCK_END_Z - IslandLayout.DOCK_START_Z
	var zc := (IslandLayout.DOCK_START_Z + IslandLayout.DOCK_END_Z) / 2.0
	_box(dock, "Deck", Vector3(IslandLayout.DOCK_X, IslandLayout.DOCK_TOP - 0.25, zc), Vector3(6.0, 0.5, length), wood)
	var z := IslandLayout.DOCK_START_Z + 2.0
	while z < IslandLayout.DOCK_END_Z:
		for s in [-1.0, 1.0]:
			_cyl(dock, "Post", Vector3(IslandLayout.DOCK_X + s * 2.8, IslandLayout.DOCK_TOP - 2.2, z), 0.22, 4.4, dark, false)
		z += 5.0
	for s in [-1.0, 1.0]:
		_cyl(dock, "Bollard", Vector3(IslandLayout.DOCK_X + s * 2.6, IslandLayout.DOCK_TOP + 0.3, IslandLayout.DOCK_END_Z - 1.0), 0.18, 0.6, dark, false)
	# gangplank from the end of the dock to the stern deck of the ship
	var ship_pos := Vector3(IslandLayout.DOCK_X, 1.0, IslandLayout.SHIP_Z)
	var deck_top := ship_pos.y + 2.85
	var z0 := IslandLayout.DOCK_END_Z
	var z1 := ship_pos.z - 8.03 + 0.4
	var run := z1 - z0
	var rise := deck_top - IslandLayout.DOCK_TOP
	var ang := atan2(rise, run)
	var top_center := Vector3(IslandLayout.DOCK_X, IslandLayout.DOCK_TOP + rise / 2.0, z0 + run / 2.0)
	var normal := Vector3(0, cos(ang), -sin(ang))
	var ramp := _body(island, "Gangplank")
	_box(ramp, "Plank", top_center - normal * 0.125, Vector3(3.4, 0.25, sqrt(run * run + rise * rise)), wood, true, Vector3(-ang, 0, 0))
	for s in [-1.0, 1.0]:
		_box(ramp, "Rail", top_center + normal * 0.5 + Vector3(s * 1.6, 0, 0), Vector3(0.08, 0.08, sqrt(run * run + rise * rise)), dark, false, Vector3(-ang, 0, 0))
	var ship := _inst("res://scenes/props/going_merry.tscn", _root, "GoingMerry", ship_pos)
	ship.add_to_group("minimap_ship", true)
	var helm := Marker3D.new()
	_add(_root, helm, "ShipHelm")
	helm.position = Vector3(ship_pos.x, deck_top, ship_pos.z - 6.6)
	# the checkpoint of the port
	var cp_pos := _on_ground(Vector2(IslandLayout.DOCK_X, 326.0))
	_checkpoint_at = cp_pos


var _checkpoint_at := Vector3.ZERO


func _checkpoint(id: String, display: String, pos: Vector3) -> Checkpoint:
	var cp := _inst("res://scenes/props/checkpoint.tscn", _root.get_node("Checkpoints"), "Checkpoint%d" % (_root.get_node("Checkpoints").get_child_count() + 1), pos) as Checkpoint
	cp.checkpoint_id = id
	cp.display_name = display
	return cp


func _collectible(scene: String, node_name: String, pos: Vector3) -> void:
	_inst(scene, _root.get_node("Collectibles"), node_name, pos)


const MEAT := "res://scenes/items/meat.tscn"
const ORANGE := "res://scenes/items/orange.tscn"
const KEY := "res://scenes/items/key.tscn"


func _items(meat: Array, oranges: Array) -> void:
	var i := 1
	for p in meat:
		_collectible(MEAT, "Meat%d" % i, _on_ground(p, 0.1))
		i += 1
	i = 1
	for p in oranges:
		_collectible(ORANGE, "Orange%d" % i, _on_ground(p, 0.1))
		i += 1


func _enemies(scene: String, prefix: String, spots: Array, drop_chance := 0.35) -> void:
	var i := 1
	var drop := load(MEAT) as PackedScene
	for p in spots:
		var e := _inst(scene, _root.get_node("MiniEnemies"), "%s%d" % [prefix, i], _on_ground(p, 0.2), _rng.randf_range(0, 360))
		e.set("drop_scene", drop)
		e.set("drop_chance", drop_chance)
		i += 1


# ------------------------------------------------------------------ vegetation
func _scatter(parent: Node, node_name: String, mesh_path: String, count: int, accept: Callable, scale_range: Vector2, vis_range: float, shadows := true, collider: StaticBody3D = null, collider_radius := 0.0, collider_height := 0.0, tilt := 0.0) -> void:
	var mesh := load(mesh_path) as Mesh
	var cells := {}
	var group := _n3(parent, node_name)
	var tries := 0
	var placed := 0
	while placed < count and tries < count * 40:
		tries += 1
		var p := Vector2(_rng.randf_range(6, 394), _rng.randf_range(6, 394))
		var h := _layout.ground(p.x, p.y)
		if not accept.call(p, h):
			continue
		var s := _rng.randf_range(scale_range.x, scale_range.y)
		var basis := Basis(Vector3.UP, _rng.randf_range(0, TAU)) * Basis.from_scale(Vector3(s, s * _rng.randf_range(0.9, 1.15), s))
		if tilt > 0.0:
			basis = Basis(Vector3.RIGHT, _rng.randf_range(-tilt, tilt)) * basis
		var cell := Vector2i(int(p.x / 50.0), int(p.y / 50.0))
		if not cells.has(cell):
			cells[cell] = []
		(cells[cell] as Array).append(Transform3D(basis, Vector3(p.x, h - 0.05, p.y)))
		placed += 1
		if collider:
			_collider(collider, _cyl_shape(collider_radius * s, collider_height * s), Vector3(p.x, h + collider_height * s / 2.0 - 0.1, p.y))
	for cell in cells:
		var list: Array = cells[cell]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = list.size()
		var origin := Vector3(cell.x * 50.0 + 25.0, 0, cell.y * 50.0 + 25.0)
		for k in list.size():
			var t: Transform3D = list[k]
			t.origin -= origin
			mm.set_instance_transform(k, t)
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.visibility_range_end = vis_range
		if not shadows:
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_add(group, mmi, "%s_%d_%d" % [node_name, cell.x, cell.y])
		mmi.position = origin
	print("  %s: %d" % [node_name, placed])


func _cyl_shape(radius: float, height: float) -> CylinderShape3D:
	var cs := CylinderShape3D.new()
	cs.radius = radius
	cs.height = height
	return cs


func _vegetation(trees: int, palms: int, bushes: int, rocks: int, grass: int) -> void:
	var island := _root.get_node("Island")
	var veg := _n3(island, "Vegetation")
	var colliders := StaticBody3D.new()
	colliders.collision_mask = 0
	_add(veg, colliders, "Colliders")
	var L := _layout
	var inland := func(p: Vector2, h: float) -> bool:
		return h > 2.4 and h < 12.0 and L.slope(p.x, p.y) < 0.45 and L.plants_allowed(p)
	var beach := func(p: Vector2, h: float) -> bool:
		return h > 0.9 and h < 2.5 and L.slope(p.x, p.y) < 0.4 and L.plants_allowed(p, -2.0)
	var anywhere := func(p: Vector2, h: float) -> bool:
		return h > 1.8 and h < 14.0 and L.slope(p.x, p.y) < 0.6 and L.plants_allowed(p, -2.0)
	if trees > 0:
		_scatter(veg, "Trees", "res://assets/generated/trees_mesh.res", trees, inland, Vector2(0.8, 1.3), 170.0, true, colliders, 0.45, 5.0)
	if palms > 0:
		_scatter(veg, "Palms", "res://assets/generated/palms_mesh.res", palms, beach, Vector2(0.8, 1.2), 170.0, true, colliders, 0.4, 5.0)
	if bushes > 0:
		_scatter(veg, "Bushes", "res://assets/generated/bushes_mesh.res", bushes, anywhere, Vector2(0.8, 1.5), 100.0, false)
	if rocks > 0:
		_scatter(veg, "Rocks", "res://assets/generated/rocks_mesh.res", rocks, anywhere, Vector2(0.9, 2.2), 150.0, true, colliders, 1.0, 1.4, 0.15)
	if grass > 0:
		_scatter(veg, "Grass", "res://assets/generated/grass_mesh.res", grass, anywhere, Vector2(0.8, 1.6), 48.0, false)


# =================================================================== Villa Syrup
func _build_syrup() -> void:
	var L := _layout
	var props := _root.get_node("Island/Props")
	var wall_mat := _m(Color(0.5, 0.48, 0.45), 0.95)
	# --- village
	for i in L.houses.size():
		_house(props, "House%d" % (i + 1), L.houses[i])
	var well := _body(props, "Well", _on_ground(IslandLayout.SYRUP_VILLAGE))
	_cyl(well, "Ring", Vector3(0, 0.5, 0), 1.3, 1.0, wall_mat)
	_cyl(well, "Water", Vector3(0, 0.95, 0), 1.0, 0.1, _m(Color(0.1, 0.3, 0.45), 0.2), false)
	for s in [-1.0, 1.0]:
		_box(well, "Post", Vector3(s * 1.1, 1.7, 0), Vector3(0.15, 1.6, 0.15), _m(Color(0.4, 0.28, 0.18)), false)
	_box(well, "Roof", Vector3(0, 2.55, 0), Vector3(3.0, 0.15, 1.6), _m(Color(0.55, 0.2, 0.15)), false)
	_village_clutter(props, IslandLayout.SYRUP_VILLAGE, 15.0)
	# lamp posts around the square
	for k in 4:
		var a := k * PI / 2.0 + PI / 4.0
		var p := IslandLayout.SYRUP_VILLAGE + Vector2(cos(a), sin(a)) * 10.5
		var lamp := _body(props, "Lamp%d" % (k + 1), _on_ground(p))
		_cyl(lamp, "Pole", Vector3(0, 1.6, 0), 0.08, 3.2, _m(Color(0.15, 0.15, 0.17)))
		_box(lamp, "Glass", Vector3(0, 3.3, 0), Vector3(0.35, 0.4, 0.35), _m(Color(1.0, 0.85, 0.5), 0.3, 2.0), false)
		_light(lamp, Vector3(0, 3.3, 0), Color(1.0, 0.8, 0.45), 1.2, 9.0)
	# signpost at the crossroads
	var sign_body := _body(props, "Signpost", _on_ground(Vector2(203, 246)))
	_cyl(sign_body, "Pole", Vector3(0, 1.4, 0), 0.1, 2.8, _m(Color(0.4, 0.28, 0.18)))
	for b in [["Mansión", 0.0, 2.4], ["Cementerio", -0.5, 2.0], ["Colina", 0.7, 1.6]]:
		_box(sign_body, "Board", Vector3(0.7, b[2], 0), Vector3(1.4, 0.35, 0.06), _m(Color(0.55, 0.4, 0.25)), false, Vector3(0, b[1], 0))
	# --- Usopp's hill
	var hill := _on_ground(IslandLayout.SYRUP_HILL)
	var look := _body(props, "Lookout", hill + Vector3(3.0, 0, -2.0))
	_box(look, "Barrel", Vector3(0, 0.6, 0), Vector3(0.9, 1.2, 0.9), _m(Color(0.45, 0.3, 0.18)))
	_box(look, "Crate", Vector3(1.2, 0.4, 0.4), Vector3(0.9, 0.8, 0.9), _m(Color(0.5, 0.38, 0.22)))
	var flag := _body(props, "HillFlag", hill + Vector3(-4.0, 0, 1.0))
	_cyl(flag, "Pole", Vector3(0, 2.5, 0), 0.08, 5.0, _m(Color(0.35, 0.25, 0.15)))
	_box(flag, "Cloth", Vector3(0.7, 4.4, 0), Vector3(1.3, 0.9, 0.04), _m(Color(0.1, 0.1, 0.1), 0.9), false)
	# --- mansion, graveyard
	_mansion()
	_graveyard()
	# --- characters, enemies and items
	var usopp := _inst("res://scenes/player/usopp.tscn", _root, "Usopp", hill + Vector3(0, 0.3, 0), -60.0)
	var kuro_points := [Vector2(-26, -4), Vector2(26, -4), Vector2(26, 22), Vector2(-26, 22)]
	var patrol := _n3(_root, "KuroPatrol")
	var m0 := IslandLayout.SYRUP_MANSION
	for i in kuro_points.size():
		var mk := Marker3D.new()
		_add(patrol, mk, "P%d" % (i + 1))
		mk.position = Vector3(m0.x + kuro_points[i].x, IslandLayout.SYRUP_MANSION_LEVEL + 0.2, m0.y + kuro_points[i].y)
	var kuro := _inst("res://scenes/enemies/kuro.tscn", _root, "Kuro", patrol.get_child(0).position, 90.0)
	kuro.set("patrol_path", NodePath("../KuroPatrol"))
	kuro.set("max_health", 420.0)
	kuro.set("dodge_chance", 0.18)
	kuro.set("xp_reward", 150)
	_enemies("res://scenes/enemies/evil_mushroom.tscn", "EvilMushroom", [Vector2(130, 170), Vector2(160, 120), Vector2(300, 270), Vector2(265, 302), Vector2(70, 140), Vector2(120, 285)])
	_enemies("res://scenes/enemies/skeleton.tscn", "Skeleton", [Vector2(318, 190), Vector2(337, 213), Vector2(322, 214), Vector2(344, 189), Vector2(302, 228), Vector2(278, 152)], 0.3)
	_items([Vector2(205, 318), Vector2(150, 250), Vector2(112, 236), Vector2(220, 215), Vector2(240, 170), Vector2(300, 235), Vector2(335, 168), Vector2(180, 150)],
		[Vector2(180, 200), Vector2(272, 215), Vector2(132, 192)])
	# the key of the mansion: on the chest inside the crypt of the graveyard
	var g := IslandLayout.SYRUP_GRAVE
	_collectible(KEY, "KeyChest", Vector3(g.x + 18.2, IslandLayout.SYRUP_GRAVE_LEVEL + 1.0, g.y))
	# --- checkpoints (the first one is where the island starts)
	_checkpoint("puerto_syrup", "Puerto de Villa Syrup", _checkpoint_at)
	_checkpoint("aldea_syrup", "Aldea de Syrup", _on_ground(Vector2(214, 288)))
	_checkpoint("colina_syrup", "Colina de Usopp", _on_ground(Vector2(102, 222)))
	_checkpoint("jardin_mansion", "Jardín de la mansión", Vector3(m0.x, IslandLayout.SYRUP_MANSION_LEVEL, m0.y + 20))
	_vegetation(260, 90, 170, 45, 2600)


func _house(parent: Node, node_name: String, h: Array) -> void:
	var pos2: Vector2 = h[0]
	var size: Vector2 = h[1]
	var height: float = h[2]
	var g := _ground(pos2)
	var body := _body(parent, node_name, Vector3(pos2.x, g - 0.3, pos2.y), float(h[3]))
	_box(body, "Walls", Vector3(0, (height + 0.3) / 2.0, 0), Vector3(size.x, height + 0.3, size.y), _m(h[4], 0.95))
	var roof := PrismMesh.new()
	roof.size = Vector3(size.x + 0.9, 2.4, size.y + 0.9)
	_mesh(body, "Roof", roof, Vector3(0, height + 0.3 + 1.2, 0), _m(h[5], 0.85))
	var door_mat := _m(Color(0.28, 0.18, 0.1))
	var glass := _m(Color(1.0, 0.9, 0.55), 0.3, 1.2)
	_box(body, "Door", Vector3(0, 1.4, size.y / 2.0 + 0.04), Vector3(1.2, 2.2, 0.1), door_mat, false)
	for s in [-1.0, 1.0]:
		_box(body, "Window", Vector3(s * size.x * 0.3, height * 0.6 + 0.3, size.y / 2.0 + 0.04), Vector3(0.9, 0.9, 0.08), glass, false)
	_box(body, "Chimney", Vector3(size.x * 0.28, height + 2.0, -size.y * 0.2), Vector3(0.7, 2.4, 0.7), _m(Color(0.45, 0.4, 0.38)), false)


func _village_clutter(parent: Node, center: Vector2, radius: float) -> void:
	var wood := _m(Color(0.5, 0.36, 0.2))
	var barrel := _m(Color(0.42, 0.28, 0.16))
	var spots := [Vector2(-9, -12), Vector2(-7, -13.5), Vector2(11, -11), Vector2(12.5, 4), Vector2(-13, 5), Vector2(8, 13), Vector2(-4, 12.5)]
	var i := 0
	for s in spots:
		var p: Vector2 = center + s * (radius / 15.0)
		var b := _body(parent, "Clutter%d" % (i + 1), _on_ground(p), _rng.randf_range(0, 360))
		if i % 2 == 0:
			_cyl(b, "Barrel", Vector3(0, 0.55, 0), 0.45, 1.1, barrel)
		else:
			_box(b, "Crate", Vector3(0, 0.4, 0), Vector3(0.9, 0.8, 0.9), wood)
		i += 1
	# a market stall
	var st := _body(parent, "Stall", _on_ground(center + Vector2(14, -2)), 270.0)
	_box(st, "Table", Vector3(0, 0.5, 0), Vector3(3.0, 1.0, 1.2), wood)
	for s in [-1.0, 1.0]:
		_box(st, "Post", Vector3(s * 1.4, 1.2, -0.5), Vector3(0.1, 2.4, 0.1), wood, false)
	_box(st, "Awning", Vector3(0, 2.4, 0), Vector3(3.4, 0.08, 1.8), _m(Color(0.7, 0.2, 0.18)), false, Vector3(0.2, 0, 0))


func _mansion() -> void:
	var c := IslandLayout.SYRUP_MANSION
	var L := IslandLayout.SYRUP_MANSION_LEVEL
	var mansion := _n3(_root, "Mansion", Vector3(c.x, L, c.y))
	var stone := _m(Color(0.62, 0.6, 0.56), 0.95)
	var dark := _m(Color(0.16, 0.16, 0.18), 0.6, 0.0, 0.6)
	var walls := _body(mansion, "Walls")
	var wh := 4.0
	_box(walls, "North", Vector3(0, wh / 2, -30), Vector3(76, wh, 1.0), stone)
	_box(walls, "West", Vector3(-38, wh / 2, 0), Vector3(1.0, wh, 61), stone)
	_box(walls, "East", Vector3(38, wh / 2, 0), Vector3(1.0, wh, 61), stone)
	_box(walls, "SouthLeft", Vector3(-21.5, wh / 2, 30), Vector3(33, wh, 1.0), stone)
	_box(walls, "SouthRight", Vector3(21.5, wh / 2, 30), Vector3(33, wh, 1.0), stone)
	for s in [-1.0, 1.0]:
		_box(walls, "GatePillar", Vector3(s * 4.9, 2.4, 30), Vector3(1.5, 4.8, 1.5), stone)
		_box(walls, "GateCap", Vector3(s * 4.9, 5.0, 30), Vector3(1.9, 0.4, 1.9), stone, false)
	# the gate: two doors that swing open (syrup_island.gd rotates Left and Right)
	var gate := _n3(mansion, "Gate", Vector3(0, 0, 30))
	for side in [["Left", -4.0, 2.0], ["Right", 4.0, -2.0]]:
		var pivot := _n3(gate, side[0], Vector3(side[1], 0, 0))
		var panel := _body(pivot, "Panel", Vector3(side[2], 0, 0))
		_box(panel, "TopRail", Vector3(0, 3.1, 0), Vector3(4.0, 0.14, 0.14), dark, false)
		_box(panel, "BottomRail", Vector3(0, 0.45, 0), Vector3(4.0, 0.14, 0.14), dark, false)
		for k in 8:
			_box(panel, "Bar", Vector3(-1.75 + k * 0.5, 1.8, 0), Vector3(0.07, 3.0, 0.07), dark, false)
		_box(panel, "Collider", Vector3(0, 1.8, 0), Vector3(4.0, 3.2, 0.3), dark, true, Vector3.ZERO)
		(panel.get_child(panel.get_child_count() - 2) as MeshInstance3D).visible = false
	# the house
	var house := _body(mansion, "House")
	var wall_col := _m(Color(0.84, 0.82, 0.74), 0.95)
	_box(house, "Walls", Vector3(0, 6.0, -20), Vector3(34, 12, 14), wall_col)
	var roof := PrismMesh.new()
	roof.size = Vector3(37, 6.0, 17)
	_mesh(house, "Roof", roof, Vector3(0, 15.0, -20), _m(Color(0.22, 0.2, 0.26), 0.8))
	_box(house, "Door", Vector3(0, 2.4, -12.9), Vector3(3.4, 4.8, 0.2), _m(Color(0.25, 0.14, 0.1)), false)
	_box(house, "Porch", Vector3(0, 0.3, -11.2), Vector3(7.0, 0.6, 3.0), stone)
	for s in [-1.0, 1.0]:
		_cyl(house, "Pillar", Vector3(s * 3.2, 2.5, -10.0), 0.4, 5.0, wall_col)
	_box(house, "PorchRoof", Vector3(0, 5.2, -11.2), Vector3(8.0, 0.3, 3.6), stone, false)
	var glass := _m(Color(0.95, 0.85, 0.5), 0.3, 1.4)
	for row in [3.5, 8.0]:
		for k in 5:
			var x := -13.0 + k * 6.5
			if row < 5.0 and absf(x) < 4.0:
				continue
			_box(house, "Window", Vector3(x, row, -12.95), Vector3(1.4, 2.0, 0.1), glass, false)
	for s in [-1.0, 1.0]:
		_cyl(house, "Turret", Vector3(s * 17.0, 7.0, -13.0), 3.0, 14.0, wall_col)
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 3.8
		cone.height = 5.0
		cone.radial_segments = 14
		_mesh(house, "TurretRoof", cone, Vector3(s * 17.0, 16.5, -13.0), _m(Color(0.22, 0.2, 0.26), 0.8))
	# garden: fountain, hedges and lamps
	var garden := _body(mansion, "Garden")
	_cyl(garden, "Basin", Vector3(0, 0.45, 12), 3.2, 0.9, stone)
	_cyl(garden, "Water", Vector3(0, 0.88, 12), 2.8, 0.1, _m(Color(0.1, 0.35, 0.5), 0.15), false)
	_cyl(garden, "Column", Vector3(0, 1.6, 12), 0.35, 2.2, stone, false)
	var hedge := _m(Color(0.12, 0.3, 0.12), 1.0)
	for s in [-1.0, 1.0]:
		_box(garden, "Hedge", Vector3(s * 11.0, 0.7, 12.0), Vector3(1.4, 1.4, 16.0), hedge)
	for s in [-1.0, 1.0]:
		for z in [-8.0, 26.0]:
			var lamp := _n3(garden, "Lamp", Vector3(s * 30.0, 0, z))
			_cyl(lamp, "Pole", Vector3(0, 1.6, 0), 0.08, 3.2, dark, false)
			_box(lamp, "Glass", Vector3(0, 3.3, 0), Vector3(0.35, 0.4, 0.35), _m(Color(1.0, 0.85, 0.5), 0.3, 2.0), false)
			_light(lamp, Vector3(0, 3.3, 0), Color(1.0, 0.8, 0.45), 1.2, 10.0)


func _graveyard() -> void:
	var c := IslandLayout.SYRUP_GRAVE
	var lv := IslandLayout.SYRUP_GRAVE_LEVEL
	var yard := _n3(_root.get_node("Island/Props"), "Graveyard", Vector3(c.x, lv, c.y))
	var iron := _m(Color(0.12, 0.12, 0.14), 0.6, 0.0, 0.5)
	var stone := _m(Color(0.5, 0.5, 0.52), 0.95)
	var moss := _m(Color(0.38, 0.42, 0.36), 1.0)
	# iron fence with a gap on the west side (towards the village)
	var fence := _body(yard, "Fence")
	for seg in [[Vector3(0, 0.7, -20), Vector3(50, 1.4, 0.15)], [Vector3(0, 0.7, 20), Vector3(50, 1.4, 0.15)], [Vector3(25, 0.7, 0), Vector3(0.15, 1.4, 40)],
			[Vector3(-25, 0.7, -11.5), Vector3(0.15, 1.4, 17)], [Vector3(-25, 0.7, 11.5), Vector3(0.15, 1.4, 17)]]:
		_box(fence, "Rail", seg[0], seg[1], iron)
	for s in [-1.0, 1.0]:
		_box(fence, "ArchPost", Vector3(-25, 1.8, s * 3.3), Vector3(0.5, 3.6, 0.5), stone)
	_box(fence, "ArchTop", Vector3(-25, 3.7, 0), Vector3(0.5, 0.5, 7.2), stone, false)
	# tombstones in rows
	var i := 0
	for x in [-17.0, -11.0, -5.0, 1.0, 7.0]:
		for z in [-13.0, -6.0, 6.0, 13.0]:
			var t := _body(yard, "Tomb%d" % (i + 1), Vector3(x + _rng.randf_range(-1, 1), 0, z + _rng.randf_range(-1, 1)), _rng.randf_range(-15, 15))
			var hh := _rng.randf_range(1.0, 1.7)
			_box(t, "Slab", Vector3(0, hh / 2.0, 0), Vector3(0.9, hh, 0.3), stone)
			_cyl(t, "Top", Vector3(0, hh, 0), 0.45, 0.3, moss, false, Vector3(PI / 2.0, 0, 0))
			i += 1
	# dead trees
	var dead := _m(Color(0.16, 0.12, 0.1), 1.0)
	for k in [[-20.0, -16.0], [-2.0, 16.0], [12.0, -10.0], [-22.0, 14.0]]:
		var t := _body(yard, "DeadTree", Vector3(k[0], 0, k[1]), _rng.randf_range(0, 360))
		_cyl(t, "Trunk", Vector3(0, 2.2, 0), 0.28, 4.4, dead, true, Vector3.ZERO, 0.12)
		_cyl(t, "BranchA", Vector3(0.7, 3.6, 0), 0.08, 2.0, dead, false, Vector3(0, 0, -0.9))
		_cyl(t, "BranchB", Vector3(-0.6, 3.2, 0.2), 0.07, 1.8, dead, false, Vector3(0, 0, 1.0))
	# the crypt where the key is kept: open to the west
	var crypt := _body(yard, "Crypt")
	_box(crypt, "Floor", Vector3(16.5, 0.05, 0), Vector3(8.5, 0.1, 8.0), stone)
	_box(crypt, "Back", Vector3(20.4, 2.2, 0), Vector3(0.8, 4.4, 8.0), stone)
	_box(crypt, "SideNorth", Vector3(16.5, 2.2, -3.6), Vector3(8.0, 4.4, 0.8), stone)
	_box(crypt, "SideSouth", Vector3(16.5, 2.2, 3.6), Vector3(8.0, 4.4, 0.8), stone)
	_box(crypt, "Roof", Vector3(16.5, 4.7, 0), Vector3(9.2, 0.6, 8.8), stone)
	var gable := PrismMesh.new()
	gable.size = Vector3(9.6, 1.8, 9.2)
	_mesh(crypt, "Gable", gable, Vector3(16.5, 5.9, 0), moss, Vector3(0, PI / 2.0, 0))
	# the chest (the key, KeyChest, rests on it)
	var chest := _body(yard, "Chest", Vector3(18.2, 0, 0))
	_box(chest, "Box", Vector3(0, 0.4, 0), Vector3(0.9, 0.8, 1.4), _m(Color(0.4, 0.26, 0.14)))
	_box(chest, "Lid", Vector3(0, 0.88, 0), Vector3(0.95, 0.16, 1.45), _m(Color(0.34, 0.22, 0.12)), false)
	_box(chest, "Band", Vector3(0, 0.5, 0), Vector3(0.97, 0.12, 0.2), _m(Color(0.85, 0.7, 0.25), 0.3, 0.0, 0.8), false)
	_light(yard, Vector3(16.0, 2.5, 0), Color(0.55, 1.0, 0.6), 1.4, 10.0)
	_light(yard, Vector3(-8.0, 3.0, 0), Color(0.6, 0.9, 1.0), 0.8, 14.0)


# =================================================================== Whisky Peak
func _build_whisky() -> void:
	var L := _layout
	var props := _root.get_node("Island/Props")
	var sand_wall := _m(Color(0.84, 0.66, 0.44), 0.95)
	for i in L.houses.size():
		_house(props, "House%d" % (i + 1), L.houses[i])
	# arch of the town entrance
	var a := IslandLayout.WHISKY_ARCH
	var arch := _body(props, "Arch", _on_ground(a))
	for s in [-1.0, 1.0]:
		_box(arch, "Pillar", Vector3(s * 6.0, 4.0, 0), Vector3(3.0, 8.0, 3.0), sand_wall)
		_box(arch, "Cap", Vector3(s * 6.0, 8.3, 0), Vector3(3.6, 0.6, 3.6), _m(Color(0.7, 0.5, 0.34)), false)
	_box(arch, "Lintel", Vector3(0, 9.5, 0), Vector3(15.5, 2.4, 3.0), sand_wall, false)
	_label(arch, "Whisky Peak", Vector3(0, 9.5, 1.6), 0.02, Color(0.3, 0.15, 0.08))
	# plaza: fountain and benches
	var p := IslandLayout.WHISKY_PLAZA
	var fountain := _body(props, "Fountain", _on_ground(p))
	_cyl(fountain, "Basin", Vector3(0, 0.5, 0), 3.6, 1.0, _m(Color(0.72, 0.62, 0.5), 0.95))
	_cyl(fountain, "Water", Vector3(0, 0.95, 0), 3.2, 0.1, _m(Color(0.12, 0.45, 0.55), 0.15), false)
	_cyl(fountain, "Column", Vector3(0, 1.8, 0), 0.4, 2.6, _m(Color(0.72, 0.62, 0.5), 0.95), false)
	for k in 4:
		var ang := k * PI / 2.0 + PI / 4.0
		var bench := _body(props, "Bench%d" % (k + 1), _on_ground(p + Vector2(cos(ang), sin(ang)) * 9.5), rad_to_deg(-ang) + 90.0)
		_box(bench, "Seat", Vector3(0, 0.5, 0), Vector3(2.2, 0.15, 0.7), _m(Color(0.45, 0.3, 0.18)))
		_box(bench, "Back", Vector3(0, 0.95, -0.3), Vector3(2.2, 0.6, 0.1), _m(Color(0.45, 0.3, 0.18)), false)
	_village_clutter(props, p, 17.0)
	# lamp posts along the street
	for z in [305.0, 285.0, 232.0]:
		for s in [-1.0, 1.0]:
			var lamp := _body(props, "Lamp", _on_ground(Vector2(200.0 + s * 7.5, z)))
			_cyl(lamp, "Pole", Vector3(0, 1.6, 0), 0.08, 3.2, _m(Color(0.15, 0.15, 0.17)))
			_box(lamp, "Glass", Vector3(0, 3.3, 0), Vector3(0.35, 0.4, 0.35), _m(Color(1.0, 0.85, 0.5), 0.3, 2.0), false)
			_light(lamp, Vector3(0, 3.3, 0), Color(1.0, 0.8, 0.45), 1.2, 9.0)
	_cactus_rocks()
	# the plateau of the great cactus: a stone ring marks the arena
	var plat := IslandLayout.WHISKY_PLATEAU
	var ring := _body(props, "ArenaStones", _on_ground(plat + Vector2(0, 14)))
	for k in 12:
		var ang := k * TAU / 12.0
		var rock := _body(ring, "Stone%d" % (k + 1), Vector3(cos(ang) * 22.0, 0.0, sin(ang) * 22.0 - 14.0))
		if Vector2(cos(ang) * 22.0, sin(ang) * 22.0 - 14.0).distance_to(Vector2(0, -30)) < 6.0:
			continue
		_box(rock, "Block", Vector3(0, 0.6, 0), Vector3(1.4, 1.2, 1.4), _m(Color(0.62, 0.42, 0.3)), true, Vector3(0, ang, 0))
	# characters and enemies
	var nami := _inst("res://scenes/player/nami.tscn", _root, "Nami", _on_ground(plat * 0 + Vector2(200, 243), 0.3), 0.0)
	var patrol := _n3(_root, "GarpPatrol")
	var lv := IslandLayout.WHISKY_PLATEAU_LEVEL
	for i in 4:
		var pts := [Vector2(176, 92), Vector2(224, 92), Vector2(224, 112), Vector2(176, 112)]
		var mk := Marker3D.new()
		_add(patrol, mk, "P%d" % (i + 1))
		mk.position = Vector3(pts[i].x, lv + 0.2, pts[i].y)
	var garp := _inst("res://scenes/enemies/garp.tscn", _root, "Garp", patrol.get_child(0).position, 90.0)
	garp.set("patrol_path", NodePath("../GarpPatrol"))
	garp.set("max_health", 480.0)
	garp.set("special_kind", "fist")
	garp.set("throw_range", 13.0)
	garp.set("damage", 22.0)
	garp.set("special_damage", 34.0)
	garp.set("walk_speed", 1.8)
	garp.set("chase_speed", 5.4)
	garp.set("attack_range", 2.6)
	garp.set("vision_range", 20.0)
	garp.set("xp_reward", 200)
	_enemies("res://scenes/enemies/evil_mushroom.tscn", "EvilMushroom", [Vector2(130, 170), Vector2(280, 165), Vector2(110, 250), Vector2(300, 262), Vector2(185, 150)])
	_items([Vector2(200, 316), Vector2(185, 285), Vector2(215, 222), Vector2(160, 215), Vector2(240, 214), Vector2(200, 160), Vector2(120, 180), Vector2(282, 182)],
		[Vector2(119, 156), Vector2(283, 157), Vector2(127, 108), Vector2(278, 98), Vector2(74, 222)])
	_checkpoint("puerto_whisky", "Puerto de Whisky Peak", _checkpoint_at)
	_checkpoint("arco_whisky", "Arco de entrada", _on_ground(Vector2(212, 294)))
	_checkpoint("plaza_whisky", "Plaza del pueblo", _on_ground(Vector2(213, 258)))
	_checkpoint("cactus_whisky", "Meseta del gran cactus", Vector3(200, lv, 122))
	_vegetation(0, 40, 110, 70, 700)


## Rocks shaped like giant cacti: a trunk, a round top and arms. [x, z, height, radius, arms]
const CACTI := [
	[200, 60, 58, 7.0, 2], [110, 150, 22, 3.6, 2], [290, 150, 26, 4.0, 2], [70, 215, 18, 3.2, 1], [330, 228, 20, 3.4, 2],
	[120, 98, 30, 4.6, 2], [285, 90, 24, 3.8, 2], [118, 288, 15, 3.0, 1], [284, 288, 16, 3.2, 1], [322, 140, 18, 3.2, 1],
	[250, 52, 28, 4.2, 2], [150, 52, 22, 3.6, 1], [62, 168, 16, 3.0, 1], [338, 188, 14, 3.0, 1],
]


func _cactus_rocks() -> void:
	var group := _n3(_root.get_node("Island"), "CactusRocks")
	var sandstone := ShaderMaterial.new()
	sandstone.shader = load("res://assets/shaders/sandstone.gdshader")
	var i := 1
	for c in CACTI:
		var pos := Vector2(c[0], c[1])
		var g := _ground(pos)
		if g < 1.5:
			continue
		var h: float = c[2]
		var r: float = c[3]
		var rock := _body(group, "Cactus%d" % i, Vector3(pos.x, g - 1.0, pos.y), _rng.randf_range(0, 360))
		var trunk := CylinderMesh.new()
		trunk.top_radius = r * 0.82
		trunk.bottom_radius = r
		trunk.height = h
		trunk.radial_segments = 14
		trunk.rings = 6
		_mesh(rock, "Trunk", trunk, Vector3(0, h / 2.0, 0), sandstone)
		var sh := CylinderShape3D.new()
		sh.radius = r * 0.9
		sh.height = h
		_collider(rock, sh, Vector3(0, h / 2.0, 0))
		var cap := SphereMesh.new()
		cap.radius = r * 0.82
		cap.height = r * 1.64
		_mesh(rock, "Top", cap, Vector3(0, h, 0), sandstone)
		for a in int(c[4]):
			var side := 1.0 if a == 0 else -1.0
			var ay := h * (0.45 + 0.18 * a)
			var reach := r * 2.1
			var ar := r * 0.42
			var arm := CylinderMesh.new()
			arm.top_radius = ar
			arm.bottom_radius = ar
			arm.height = reach
			arm.radial_segments = 10
			_mesh(rock, "Arm%d" % a, arm, Vector3(side * reach / 2.0, ay, 0), sandstone, Vector3(0, 0, PI / 2.0))
			var up_h := h * 0.28
			var up := CylinderMesh.new()
			up.top_radius = ar
			up.bottom_radius = ar
			up.height = up_h
			up.radial_segments = 10
			_mesh(rock, "ArmUp%d" % a, up, Vector3(side * reach, ay + up_h / 2.0, 0), sandstone)
			var tip := SphereMesh.new()
			tip.radius = ar
			tip.height = ar * 2.0
			_mesh(rock, "ArmTip%d" % a, tip, Vector3(side * reach, ay + up_h, 0), sandstone)
			var asx := CylinderShape3D.new()
			asx.radius = ar
			asx.height = reach
			_collider(rock, asx, Vector3(side * reach / 2.0, ay, 0), Vector3(0, 0, PI / 2.0))
			var asy := CylinderShape3D.new()
			asy.radius = ar
			asy.height = up_h
			_collider(rock, asy, Vector3(side * reach, ay + up_h / 2.0, 0))
		i += 1
