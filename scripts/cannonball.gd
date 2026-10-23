class_name CannonBall
extends Node3D
## Cannonball thrown by Garp: flies in an arc to where the player was and explodes on the ground,
## hurting the players close to it. Made in code (see Boss._throw()).

const FLIGHT_TIME := 1.1
const RADIUS := 2.4

var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _t := 0.0
var _damage := 20.0
var _shadow: MeshInstance3D


func launch(from: Vector3, to: Vector3, damage: float) -> void:
	_from = from
	_to = to
	_damage = damage
	global_position = from
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.32
	sm.height = 0.64
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.12, 0.12, 0.13)
	mat.metallic = 0.6
	mat.roughness = 0.35
	sm.material = mat
	mi.mesh = sm
	add_child(mi)
	# a red mark where it will fall
	FX.ring(get_parent(), to, RADIUS, Color(1, 0.25, 0.2, 0.7), FLIGHT_TIME)


func _process(delta: float) -> void:
	_t += delta / FLIGHT_TIME
	var p := _from.lerp(_to, _t)
	p.y += sin(clampf(_t, 0.0, 1.0) * PI) * 5.0
	global_position = p
	rotation.x += delta * 8.0
	if _t >= 1.0:
		_explode()


func _explode() -> void:
	FX.burst(get_parent(), _to + Vector3(0, 0.4, 0), Color(1.0, 0.55, 0.15), 30, 6.0, 0.18, -8.0, 0.6)
	FX.burst(get_parent(), _to + Vector3(0, 0.4, 0), Color(0.3, 0.3, 0.3), 20, 3.0, 0.3, 1.0, 1.2)
	FX.ring(get_parent(), _to, RADIUS, Color(1, 0.7, 0.3, 0.9), 0.4)
	var s := AudioStreamPlayer3D.new()
	s.stream = load("res://assets/audio/punch.wav")
	s.pitch_scale = 0.55
	s.unit_size = 14.0
	get_parent().add_child(s)
	s.global_position = _to
	s.play()
	s.finished.connect(s.queue_free)
	for n in get_tree().get_nodes_in_group("players"):
		var pl := n as Player
		if pl and not pl.dead and pl.control != Player.Controller.NONE and pl.global_position.distance_to(_to) < RADIUS:
			pl.receive_hit(_damage, _to)
	queue_free()
