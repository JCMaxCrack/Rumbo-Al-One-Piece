class_name Meshes
extends RefCounted
## Basic mesh helpers (boxes, spheres, cylinders and colored pieces).

static var _mats: Dictionary = {}


static func mat(c: Color, rough: float = 0.9, unshaded: bool = false) -> StandardMaterial3D:
	var k := "%s_%s_%s" % [c.to_html(), rough, unshaded]
	if _mats.has(k):
		return _mats[k]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if c.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mats[k] = m
	return m


static func box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


static func sphere(r: float, segs: int = 10, rings: int = 6) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = segs
	s.rings = rings
	return s


static func cyl(top: float, bottom: float, h: float, segs: int = 8) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = segs
	c.rings = 1
	return c


static func capsule(r: float, h: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = h
	c.radial_segments = 10
	c.rings = 4
	return c


## Adds a piece to a node (colored MeshInstance3D).
static func part(parent: Node3D, mesh: Mesh, pos: Vector3, c: Color, rot: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE, m: Material = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	mi.material_override = m if m else mat(c)
	parent.add_child(mi)
	return mi


## Adds a piece to a combined ArrayMesh (for MultiMesh: thousands of trees in one draw call).
static func add_to(am: ArrayMesh, prim: PrimitiveMesh, xf: Transform3D, c: Color) -> void:
	var arrays := prim.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for i in verts.size():
		verts[i] = xf * verts[i]
		norms[i] = (xf.basis * norms[i]).normalized()
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TANGENT] = null
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	am.surface_set_material(am.get_surface_count() - 1, mat(c))


static func xf(pos: Vector3, scl: Vector3 = Vector3.ONE, rot: Vector3 = Vector3.ZERO) -> Transform3D:
	return Transform3D(Basis.from_euler(rot).scaled(scl), pos)
