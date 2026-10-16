class_name Veg
extends RefCounted
## Realistic vegetation and rocks made by code (irregular shapes with noise).

static var _noise: FastNoiseLite


static func _n() -> FastNoiseLite:
	if _noise == null:
		_noise = FastNoiseLite.new()
		_noise.frequency = 0.9
		_noise.fractal_octaves = 3
	return _noise


## Sphere deformed with noise (tree crowns, bushes, rocks).
static func blob_arrays(r: float, segs: int, rings: int, amp: float, seed_off: float, squash: Vector3 = Vector3.ONE) -> Array:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = segs
	s.rings = rings
	var arrays := s.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var n := _n()
	for i in verts.size():
		var v := verts[i]
		var d := n.get_noise_3d(v.x * 1.7 + seed_off, v.y * 1.7, v.z * 1.7) * amp
		verts[i] = (v + norms[i] * d * r) * squash
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TANGENT] = null
	return arrays


static func _add(am: ArrayMesh, arrays: Array, xf: Transform3D, m: Material, flat: bool = false) -> void:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for i in verts.size():
		verts[i] = xf * verts[i]
		norms[i] = (xf.basis * norms[i]).normalized()
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TANGENT] = null
	if flat:
		var st := SurfaceTool.new()
		st.create_from_arrays(arrays)
		st.deindex()
		st.generate_normals()
		st.generate_tangents()
		st.set_material(m)
		st.commit(am)
	else:
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	am.surface_set_material(am.get_surface_count() - 1, m)


static func _prim(am: ArrayMesh, prim: PrimitiveMesh, xf: Transform3D, m: Material) -> void:
	_add(am, prim.get_mesh_arrays(), xf, m)


static func _xf(pos: Vector3, rot: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> Transform3D:
	return Transform3D(Basis.from_euler(rot).scaled(scl), pos)


static func broadleaf(leaf: Color, variant: int = 0) -> ArrayMesh:
	var am := ArrayMesh.new()
	var bark := Mat.bark()
	var fol := Mat.foliage(leaf)
	_prim(am, Meshes.cyl(0.18, 0.32, 3.4, 8), _xf(Vector3(0, 1.7, 0), Vector3(0.05, 0, 0.04)), bark)
	_prim(am, Meshes.cyl(0.07, 0.14, 1.8, 6), _xf(Vector3(0.55, 3.1, 0.1), Vector3(0, 0, -0.9)), bark)
	_prim(am, Meshes.cyl(0.06, 0.12, 1.6, 6), _xf(Vector3(-0.45, 3.3, -0.3), Vector3(0.4, 0, 0.8)), bark)
	var blobs := [[Vector3(0, 4.6, 0), 1.7], [Vector3(1.2, 4.0, 0.4), 1.2], [Vector3(-1.1, 4.2, -0.5), 1.3],
		[Vector3(0.3, 5.5, -0.6), 1.2], [Vector3(-0.4, 3.9, 1.0), 1.1], [Vector3(0.8, 5.0, 1.0), 1.0]]
	for i in blobs.size():
		var b: Array = blobs[i]
		_add(am, blob_arrays(float(b[1]), 12, 8, 0.45, i * 3.1 + variant * 17.0, Vector3(1, 0.8, 1)), _xf(b[0]), fol)
	return am


static func palm(leaf: Color) -> ArrayMesh:
	var am := ArrayMesh.new()
	var bark := Mat.textured("palmbark", Color(0.35, 0.27, 0.17), Color(0.6, 0.5, 0.35), 0.08, 1.0, 10.0, 1.2, Vector2(1, 0.3))
	var fol := Mat.foliage(leaf.lightened(0.05))
	var top := Vector3.ZERO
	for i in 7:
		var p := Vector3(i * i * 0.028, i * 0.95 + 0.45, 0)
		_prim(am, Meshes.cyl(0.14 - i * 0.008, 0.17 - i * 0.008, 1.0, 8), _xf(p, Vector3(0, 0, -0.06 * i)), bark)
		top = p + Vector3(0.05, 0.5, 0)
	_add(am, blob_arrays(0.28, 8, 5, 0.2, 3.0), _xf(top), Mat.wood(Color(0.35, 0.3, 0.12)))
	for k in 9:
		var a := k * TAU / 9.0
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var segs := 8
		var length := 3.4
		var prev_l := Vector3.ZERO
		var prev_r := Vector3.ZERO
		for j in segs + 1:
			var t := float(j) / segs
			var dist := t * length
			var droop := -t * t * 1.8
			var width := sin(t * PI) * 0.45 + 0.03
			var c := Vector3(cos(a) * dist, droop, sin(a) * dist)
			var side := Vector3(-sin(a), 0.1, cos(a)) * width
			var l := c + side
			var r := c - side
			if j > 0:
				for v in [prev_l, prev_r, r, prev_l, r, l]:
					st.set_normal(Vector3.UP)
					st.add_vertex(top + v)
			prev_l = l
			prev_r = r
		st.set_material(fol)
		st.commit(am)
		am.surface_set_material(am.get_surface_count() - 1, fol)
	return am


static func pine(leaf: Color) -> ArrayMesh:
	var am := ArrayMesh.new()
	var fol := Mat.foliage(leaf.darkened(0.25))
	_prim(am, Meshes.cyl(0.12, 0.26, 3.0, 7), _xf(Vector3(0, 1.5, 0)), Mat.bark())
	for i in 4:
		var r := 2.0 - i * 0.42
		var cone := Meshes.cyl(0.02, r, 2.0, 10)
		var arrays := cone.get_mesh_arrays()
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for v in verts.size():
			var q := verts[v]
			verts[v] = q + Vector3(q.x, 0, q.z) * _n().get_noise_3d(q.x * 3.0, q.y * 3.0 + i, q.z * 3.0) * 0.35
		arrays[Mesh.ARRAY_VERTEX] = verts
		_add(am, arrays, _xf(Vector3(0, 2.6 + i * 1.25, 0)), fol)
	return am


static func rock(variant: int = 0) -> ArrayMesh:
	var am := ArrayMesh.new()
	_add(am, blob_arrays(1.0, 10, 7, 0.55, variant * 5.3, Vector3(1.3, 0.75, 1.0)), _xf(Vector3(0, 0.35, 0)), Mat.rock(), true)
	_add(am, blob_arrays(0.55, 8, 6, 0.5, variant * 5.3 + 2.0), _xf(Vector3(0.8, 0.2, 0.4)), Mat.rock(), true)
	return am


static func bush(leaf: Color) -> ArrayMesh:
	var am := ArrayMesh.new()
	var fol := Mat.foliage(leaf.darkened(0.1))
	for i in 4:
		var a := i * 1.7
		_add(am, blob_arrays(0.6 - i * 0.05, 10, 7, 0.5, i * 2.3, Vector3(1, 0.75, 1)), _xf(Vector3(cos(a) * 0.4, 0.45 + i * 0.05, sin(a) * 0.4)), fol)
	return am


static func grass_clump() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for i in 7:
		var a := rng.randf() * TAU
		var base := Vector3(rng.randf_range(-0.25, 0.25), 0, rng.randf_range(-0.25, 0.25))
		var h := rng.randf_range(0.16, 0.38)
		var w := 0.035
		var dir := Vector3(cos(a), 0, sin(a))
		var side := Vector3(-dir.z, 0, dir.x) * w
		var tip := base + dir * rng.randf_range(0.05, 0.15) + Vector3(0, h, 0)
		for v in [base - side, base + side, tip]:
			st.set_normal(Vector3.UP)
			st.add_vertex(v)
	st.set_material(Mat.grass_blades())
	return st.commit()


static func flowers() -> ArrayMesh:
	var am := ArrayMesh.new()
	var cols := [Color(1, 0.85, 0.2), Color(0.95, 0.4, 0.55), Color(1, 1, 1), Color(0.65, 0.5, 1)]
	for i in 6:
		var a := i * 1.3
		var p := Vector3(cos(a) * 0.5, 0.25, sin(a) * 0.45)
		_prim(am, Meshes.cyl(0.01, 0.01, 0.25, 4), _xf(p - Vector3(0, 0.12, 0)), Meshes.mat(Color(0.2, 0.45, 0.15)))
		_prim(am, Meshes.sphere(0.06, 6, 3), _xf(p), Meshes.mat(cols[i % cols.size()]))
	return am
