class_name Pellet
extends Area3D
## Usopp's slingshot pellet: flies straight, hits the first enemy it touches and disappears.
## Made in code (see Player._shoot()).

var direction := Vector3.FORWARD
var damage := 12.0
var speed := 26.0
var life := 1.2
var shooter: Node3D


func _ready() -> void:
	collision_layer = 0
	collision_mask = 1 | 4
	monitorable = false
	var shape := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 0.18
	shape.shape = sph
	add_child(shape)
	var mi := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.09
	mesh.height = 0.18
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.35, 0.3, 0.25)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.8, 0.4)
	mat.emission_energy_multiplier = 0.4
	mesh.material = mat
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	global_position += direction * speed * delta
	life -= delta
	if life <= 0.0:
		queue_free()


func _on_body_entered(body: Node3D) -> void:
	if body == shooter or body is Player:
		return
	if body.has_method("receive_hit"):
		body.receive_hit(damage, global_position - direction)
	FX.burst(get_parent(), global_position, Color(0.9, 0.8, 0.6), 8, 2.5, 0.06, -6.0, 0.35)
	queue_free()
