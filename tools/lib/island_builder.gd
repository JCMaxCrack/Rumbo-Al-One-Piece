class_name IslandBuilder
extends RefCounted
## EDITOR TOOL (not used while playing): builds the island nodes for scenes/game.tscn.
## Terrain, water, vegetation, props, colliders and borders are created as nodes and the
## heavy resources (meshes, shapes) are saved to assets/generated/.

const SIZE := 140.0
const CENTER := 70.0
const RES := 1.0
const LAND_RADIUS := 40.0
const BEACH_RADIUS := 50.0
const BORDER_RADIUS := 49.0
const PATROL_LEFT := Vector3(CENTER - 13.0, 0, CENTER - 12.0)
const PATROL_RIGHT := Vector3(CENTER + 13.0, 0, CENTER - 12.0)
const PLAYER_START := Vector3(CENTER, 0, CENTER + 22.0)

var n_verts := 0
var heights := PackedFloat32Array()
var noise := FastNoiseLite.new()
var owner: Node
var saver: Callable  # func(resource, path) that saves meshes/materials


func _init(scene_owner: Node, save_func: Callable) -> void:
	owner = scene_owner
	saver = save_func
	noise.seed = 7
	noise.frequency = 0.035
	n_verts = int(SIZE / RES) + 1
	heights.resize(n_verts * n_verts)
	for iz in n_verts:
		for ix in n_verts:
			heights[iz * n_verts + ix] = raw_height(ix * RES, iz * RES)


func _own(n: Node) -> Node:
	n.owner = owner
	for c in n.get_children():
		_own(c)
	return n


func add(parent: Node, n: Node, node_name: String) -> Node:
	n.name = node_name
	parent.add_child(n)
	_own(n)
	return n


static func dist_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return p.distance_to(a + ab * t)


func raw_height(x: float, z: float) -> float:
	var d := Vector2(x - CENTER, z - CENTER).length()
	var n := noise.get_noise_2d(x, z)
	var h: float
	if d < LAND_RADIUS:
		h = 0.9 + n * 0.6
	elif d < BEACH_RADIUS:
		var t := (d - LAND_RADIUS) / (BEACH_RADIUS - LAND_RADIUS)
		h = lerpf(0.9 + n * 0.6, -0.5, smoothstep(0.0, 1.0, t))
	else:
		h = lerpf(-0.5, -4.0, clampf((d - BEACH_RADIUS) / 12.0, 0.0, 1.0))
	var hill := Vector2(x - CENTER, z - (CENTER - 32.0)).length()
	h += maxf(0.0, 1.0 - hill / 16.0) * 9.0 * (0.85 + 0.3 * n)
	var flat := minf(dist_to_segment(Vector2(x, z), Vector2(PATROL_LEFT.x, PATROL_LEFT.z), Vector2(PATROL_RIGHT.x, PATROL_RIGHT.z)), Vector2(x - PLAYER_START.x, z - PLAYER_START.z).length())
	var k := clampf((flat - 4.0) / 6.0, 0.0, 1.0)
	return lerpf(1.0, h, k) if d < LAND_RADIUS else h


func height_at(x: float, z: float) -> float:
	var fx := clampf(x / RES, 0.0, n_verts - 1.001)
	var fz := clampf(z / RES, 0.0, n_verts - 1.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	return lerpf(lerpf(heights[iz * n_verts + ix], heights[iz * n_verts + ix + 1], tx), lerpf(heights[(iz + 1) * n_verts + ix], heights[(iz + 1) * n_verts + ix + 1], tx), tz)


func ground(p: Vector3) -> Vector3:
	return Vector3(p.x, height_at(p.x, p.z), p.z)


func build(parent: Node3D) -> Node3D:
	var island := add(parent, Node3D.new(), "Island") as Node3D
	_terrain(island)
	_water(island)
	_vegetation(island)
	_props(island)
	_borders(island)
	return island


func _terrain(island: Node3D) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pa := Vector2(PATROL_LEFT.x, PATROL_LEFT.z)
	var pb := Vector2(PATROL_RIGHT.x, PATROL_RIGHT.z)
	for iz in n_verts:
		for ix in n_verts:
			var x := ix * RES
			var z := iz * RES
			var d := Vector2(x - CENTER, z - CENTER).length()
			var sand := clampf((d - (LAND_RADIUS - 2.0)) / 5.0, 0.0, 1.0)
			var on_path := dist_to_segment(Vector2(x, z), pa, pb) < 2.2 or dist_to_segment(Vector2(x, z), Vector2(PLAYER_START.x, PLAYER_START.z), Vector2(CENTER, PATROL_LEFT.z)) < 1.4
			st.set_color(Color(sand, 1.0 if on_path and d < LAND_RADIUS else 0.0, 0.0, 1.0))
			st.set_uv(Vector2(x, z))
			st.add_vertex(Vector3(x, heights[iz * n_verts + ix], z))
	for iz in n_verts - 1:
		for ix in n_verts - 1:
			var i := iz * n_verts + ix
			for k in [i, i + 1, i + n_verts, i + 1, i + n_verts + 1, i + n_verts]:
				st.add_index(k)
	st.generate_normals()
	st.generate_tangents()
	var mesh := st.commit()
	mesh.surface_set_material(0, Mat.terrain())
	saver.call(mesh, "res://assets/generated/terrain_mesh.res")
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	add(island, mi, "Terrain")
	var body := add(island, StaticBody3D.new(), "TerrainBody") as StaticBody3D
	body.collision_layer = 1
	body.collision_mask = 0
	var hm := HeightMapShape3D.new()
	hm.map_width = n_verts
	hm.map_depth = n_verts
	hm.map_data = heights
	saver.call(hm, "res://assets/generated/terrain_shape.res")
	var cs := CollisionShape3D.new()
	cs.shape = hm
	cs.position = Vector3(SIZE / 2.0, 0, SIZE / 2.0)
	add(body, cs, "CollisionShape3D")


func _water(island: Node3D) -> void:
	var img := Image.create(64, 64, false, Image.FORMAT_L8)
	for y in 64:
		for x in 64:
			var d := Vector2((x + 0.5) / 64.0 * SIZE - CENTER, (y + 0.5) / 64.0 * SIZE - CENTER).length()
			img.set_pixel(x, y, Color.WHITE * clampf(1.0 - (d - BEACH_RADIUS + 6.0) / 12.0, 0.0, 1.0))
	var tex := ImageTexture.create_from_image(img)
	saver.call(tex, "res://assets/generated/shore_mask.res")
	var mat := Mat.water(tex, Vector2(SIZE, SIZE))
	var pm := PlaneMesh.new()
	pm.size = Vector2(SIZE + 600, SIZE + 600)
	pm.subdivide_width = 160
	pm.subdivide_depth = 160
	pm.material = mat
	saver.call(pm, "res://assets/generated/water_mesh.res")
	var mi := MeshInstance3D.new()
	mi.mesh = pm
	mi.position = Vector3(CENTER, 0, CENTER)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add(island, mi, "Water")


func _clear_zone(p: Vector3) -> bool:
	var q := Vector2(p.x, p.z)
	if dist_to_segment(q, Vector2(PATROL_LEFT.x, PATROL_LEFT.z), Vector2(PATROL_RIGHT.x, PATROL_RIGHT.z)) < 7.0:
		return true
	return dist_to_segment(q, Vector2(PLAYER_START.x, PLAYER_START.z), Vector2(CENTER, PATROL_LEFT.z)) < 6.0


func _vegetation(island: Node3D) -> void:
	var veg := add(island, Node3D.new(), "Vegetation")
	var colliders := add(island, StaticBody3D.new(), "VegetationColliders") as StaticBody3D
	colliders.collision_layer = 1
	colliders.collision_mask = 0
	var leaf := Color(0.2, 0.42, 0.14)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var palms := []
	var trees := []
	var rocks := []
	var bushes := []
	for i in 400:
		var a := rng.randf() * TAU
		var d := sqrt(rng.randf()) * BEACH_RADIUS
		var p := Vector3(CENTER + cos(a) * d, 0, CENTER + sin(a) * d)
		if _clear_zone(p):
			continue
		if d > LAND_RADIUS - 3.0 and d < BEACH_RADIUS - 4.0 and palms.size() < 26:
			palms.append(p)
		elif d < LAND_RADIUS - 6.0 and trees.size() < 30:
			trees.append(p)
		elif d < LAND_RADIUS and rocks.size() < 14 and rng.randf() < 0.3:
			rocks.append(p)
		elif d < LAND_RADIUS - 2.0 and bushes.size() < 30:
			bushes.append(p)
	_multi(veg, colliders, "Palms", Veg.palm(leaf), palms, 0.9, 1.2, 0.22, rng)
	_multi(veg, colliders, "Trees", Veg.broadleaf(leaf, 0), trees, 0.8, 1.15, 0.34, rng)
	_multi(veg, colliders, "Rocks", Veg.rock(0), rocks, 0.8, 1.6, 0.9, rng, -0.2)
	_multi(veg, colliders, "Bushes", Veg.bush(leaf), bushes, 0.8, 1.3, 0.0, rng)
	var grass := []
	for i in 2500:
		var a2 := rng.randf() * TAU
		var d2 := sqrt(rng.randf()) * (LAND_RADIUS - 1.0)
		var p2 := Vector3(CENTER + cos(a2) * d2, 0, CENTER + sin(a2) * d2)
		if dist_to_segment(Vector2(p2.x, p2.z), Vector2(PATROL_LEFT.x, PATROL_LEFT.z), Vector2(PATROL_RIGHT.x, PATROL_RIGHT.z)) > 2.5:
			grass.append(p2)
	_multi(veg, colliders, "Grass", Veg.grass_clump(), grass, 0.7, 1.4, 0.0, rng, 0.0, 60.0)


func _multi(veg: Node, colliders: Node, node_name: String, mesh: Mesh, points: Array, smin: float, smax: float, col_radius: float, rng: RandomNumberGenerator, yoff: float = 0.0, vis_range: float = 0.0) -> void:
	saver.call(mesh, "res://assets/generated/%s_mesh.res" % node_name.to_lower())
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = points.size()
	for i in points.size():
		var p: Vector3 = points[i]
		var s := rng.randf_range(smin, smax)
		p.y = height_at(p.x, p.z) + yoff
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), p))
		if col_radius > 0.0:
			var cy := CylinderShape3D.new()
			cy.radius = col_radius * s
			cy.height = 5.0 * s
			var cs := CollisionShape3D.new()
			cs.shape = cy
			cs.position = p + Vector3(0, 2.5 * s - 0.3, 0)
			add(colliders, cs, "%sCollider%d" % [node_name.trim_suffix("s"), i + 1])
	saver.call(mm, "res://assets/generated/%s_multimesh.res" % node_name.to_lower())
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	if vis_range > 0.0:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = vis_range
		mmi.visibility_range_end_margin = 8.0
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	add(veg, mmi, node_name)


func _prop_body(parent: Node, node_name: String, shape: Shape3D, offset: Vector3) -> void:
	var body := add(parent, StaticBody3D.new(), node_name) as StaticBody3D
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = offset
	add(body, cs, "CollisionShape3D")


func _mesh_node(parent: Node, node_name: String, mesh: PrimitiveMesh, pos: Vector3, mat: Material) -> MeshInstance3D:
	mesh.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	add(parent, mi, node_name)
	return mi


func _props(island: Node3D) -> void:
	var props := add(island, Node3D.new(), "Props")
	var idx := 0
	for end in [PATROL_LEFT, PATROL_RIGHT]:
		var side := signf(end.x - CENTER)
		var flag := add(props, Node3D.new(), "Flag%d" % (idx + 1)) as Node3D
		flag.position = ground(end + Vector3(side * 3.5, 0, -2.5))
		_mesh_node(flag, "Pole", Meshes.cyl(0.07, 0.1, 5.0, 8), Vector3(0, 2.5, 0), Mat.wood(Color(0.4, 0.27, 0.15)))
		_mesh_node(flag, "Cloth", Meshes.box(Vector3(1.6, 1.0, 0.04)), Vector3(0.82, 4.4, 0), Mat.cloth(Color(0.12, 0.12, 0.14)))
		var pole_shape := CylinderShape3D.new()
		pole_shape.radius = 0.15
		pole_shape.height = 5.0
		_prop_body(flag, "StaticBody3D", pole_shape, Vector3(0, 2.5, 0))
		for k in 3:
			idx += 1
			var pos := ground(end + Vector3(side * (2.0 + k * 0.9), 0, -4.0 + k * 0.6))
			if k % 2 == 0:
				var crate := add(props, Node3D.new(), "Crate%d" % idx) as Node3D
				crate.position = pos
				crate.rotation.y = k * 0.7
				_mesh_node(crate, "Mesh", Meshes.box(Vector3(0.9, 0.9, 0.9)), Vector3(0, 0.45, 0), Mat.wood(Color(0.55, 0.42, 0.26)))
				var bs := BoxShape3D.new()
				bs.size = Vector3(0.9, 0.9, 0.9)
				_prop_body(crate, "StaticBody3D", bs, Vector3(0, 0.45, 0))
			else:
				var barrel := add(props, Node3D.new(), "Barrel%d" % idx) as Node3D
				barrel.position = pos
				_mesh_node(barrel, "Mesh", Meshes.cyl(0.38, 0.38, 1.0, 12), Vector3(0, 0.5, 0), Mat.wood(Color(0.45, 0.3, 0.17)))
				_mesh_node(barrel, "RingTop", Meshes.cyl(0.4, 0.4, 0.07, 12), Vector3(0, 0.85, 0), Mat.metal(Color(0.25, 0.25, 0.27)))
				_mesh_node(barrel, "RingBottom", Meshes.cyl(0.4, 0.4, 0.07, 12), Vector3(0, 0.15, 0), Mat.metal(Color(0.25, 0.25, 0.27)))
				var cy := CylinderShape3D.new()
				cy.radius = 0.4
				cy.height = 1.0
				_prop_body(barrel, "StaticBody3D", cy, Vector3(0, 0.5, 0))
		idx += 1


func _borders(island: Node3D) -> void:
	var body := add(island, StaticBody3D.new(), "Borders") as StaticBody3D
	body.collision_layer = 1
	body.collision_mask = 0
	var count := 48
	var bs := BoxShape3D.new()
	bs.size = Vector3(TAU * BORDER_RADIUS / count + 0.6, 12.0, 1.0)
	for i in count:
		var a := i * TAU / count
		var cs := CollisionShape3D.new()
		cs.shape = bs
		cs.position = Vector3(CENTER + cos(a) * BORDER_RADIUS, 4.0, CENTER + sin(a) * BORDER_RADIUS)
		cs.rotation.y = -a + PI / 2.0
		add(body, cs, "Wall%d" % (i + 1))
