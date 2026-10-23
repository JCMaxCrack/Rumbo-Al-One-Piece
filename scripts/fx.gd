class_name FX
extends RefCounted
## Small visual effects made in code (no scene needed): particle bursts, shock rings and the
## floating texts of damage, experience and level ups. CPUParticles3D are used so the effects
## also work with the Compatibility renderer of phones. Every effect frees itself.


static func _mat(color: Color, unshaded := true) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	return m


## A burst of small pieces (hits, food crumbs, dust...).
static func burst(parent: Node, pos: Vector3, color: Color, amount := 16, speed := 3.0, size := 0.08, gravity := -6.0, life := 0.7) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.9
	p.amount = amount
	p.lifetime = life
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = speed * 0.5
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, gravity, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.2
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	q.material = _mat(color)
	p.mesh = q
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0))
	p.scale_amount_curve = curve
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	p.finished.connect(p.queue_free)
	return p


## Pieces of food while eating.
static func crumbs(parent: Node, pos: Vector3) -> void:
	burst(parent, pos, Color(0.72, 0.38, 0.16), 14, 2.2, 0.06, -9.0, 0.6)
	burst(parent, pos, Color(1.0, 0.85, 0.55), 6, 1.6, 0.05, -9.0, 0.5)


## Green sparkles going up (health back).
static func heal(parent: Node, pos: Vector3) -> void:
	var p := burst(parent, pos, Color(0.4, 1.0, 0.45), 18, 1.4, 0.09, 2.5, 1.0)
	p.spread = 180.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.45


## A ring on the ground that grows and fades (shock waves of the skills and of the bosses).
static func ring(parent: Node, pos: Vector3, radius: float, color: Color, time := 0.45) -> void:
	var mi := MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = 0.85
	t.outer_radius = 1.0
	t.rings = 32
	t.ring_segments = 6
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = color
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	t.material = m
	mi.mesh = t
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.global_position = pos + Vector3(0, 0.1, 0)
	mi.scale = Vector3(radius * 0.15, 0.4, radius * 0.15)
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(radius, 0.4, radius), time).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(m, "albedo_color:a", 0.0, time)
	tw.chain().tween_callback(mi.queue_free)


## Text that floats up and fades ("+12 XP", "¡Nivel 3!", damage numbers).
static func text(parent: Node, pos: Vector3, msg: String, color := Color.WHITE, size := 48, time := 1.1) -> void:
	var l := Label3D.new()
	l.text = msg
	l.font_size = size
	l.pixel_size = 0.006
	l.outline_size = 12
	l.modulate = color
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	parent.add_child(l)
	l.global_position = pos
	var tw := l.create_tween().set_parallel(true)
	tw.tween_property(l, "global_position", pos + Vector3(0, 1.0, 0), time).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, time).set_delay(time * 0.5)
	tw.chain().tween_callback(l.queue_free)


## Golden column of sparkles (level up).
static func level_up(parent: Node, pos: Vector3) -> void:
	var p := burst(parent, pos + Vector3(0, 0.2, 0), Color(1.0, 0.85, 0.3), 40, 3.5, 0.1, 1.5, 1.4)
	p.spread = 25.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	p.emission_ring_axis = Vector3.UP
	p.emission_ring_radius = 0.6
	p.emission_ring_inner_radius = 0.5
	p.emission_ring_height = 0.1
	ring(parent, pos, 2.2, Color(1.0, 0.85, 0.3, 0.8), 0.7)
