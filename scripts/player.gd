class_name Player
extends CharacterBody3D
## Luffy (beta): walk, sprint and jump. No attacks.
## Nodes used (see scenes/player/luffy.tscn):
##   Model (the luffy.fbx instance), AnimationPlayer (animations library "luffy"),
##   CameraPivot/SpringArm3D/Camera3D, HurtSound, JumpSound, InvulnerabilityTimer, HurtTimer.

signal health_changed(current: float, maximum: float)
signal died

@export var max_health := 100.0
@export var walk_speed := 3.2
@export var run_speed := 6.8
@export var jump_velocity := 7.5
@export var gravity := 22.0
@export var mouse_sensitivity := 0.003
@export var knockback_force := 9.0
## The Mixamo jump starts with a crouch: it is skipped so the animation matches the physics.
@export var jump_anim_start := 0.12
@export var jump_anim_speed := 1.15

@onready var model: Node3D = $Model
@onready var anim: AnimationPlayer = $AnimationPlayer
@onready var camera_pivot: Node3D = $CameraPivot
@onready var spring_arm: SpringArm3D = $CameraPivot/SpringArm3D
@onready var camera: Camera3D = $CameraPivot/SpringArm3D/Camera3D
@onready var hurt_sound: AudioStreamPlayer3D = $HurtSound
@onready var jump_sound: AudioStreamPlayer3D = $JumpSound
@onready var invulnerability_timer: Timer = $InvulnerabilityTimer
@onready var hurt_timer: Timer = $HurtTimer

var health := 100.0
var facing := Vector3.FORWARD
var knockback := Vector3.ZERO
var dead := false
var controls_enabled := true
var _current_anim := ""
var _shake := 0.0


func _ready() -> void:
	add_to_group("player")
	health = max_health
	health_changed.emit(health, max_health)
	_play("idle")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_look((event as InputEventMouseMotion).relative)


func _look(rel: Vector2) -> void:
	camera_pivot.rotation.y -= rel.x * mouse_sensitivity
	spring_arm.rotation.x = clampf(spring_arm.rotation.x - rel.y * mouse_sensitivity, -1.1, 0.35)


func _process(delta: float) -> void:
	var stick := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if stick.length() > 0.1:
		_look(stick * 900.0 * delta)
	# blink while invulnerable
	model.visible = invulnerability_timer.is_stopped() or int(invulnerability_timer.time_left * 16.0) % 2 == 0
	if _shake > 0.0:
		camera.h_offset = randf_range(-1.0, 1.0) * _shake
		camera.v_offset = randf_range(-1.0, 1.0) * _shake
		_shake = move_toward(_shake, 0.0, delta * 1.6)
	else:
		camera.h_offset = 0.0
		camera.v_offset = 0.0


func _physics_process(delta: float) -> void:
	var can_move := controls_enabled and not dead and hurt_timer.is_stopped()
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back") if can_move else Vector2.ZERO
	var basis_y := camera_pivot.global_transform.basis
	var forward := Vector3(-basis_y.z.x, 0, -basis_y.z.z).normalized()
	var right := Vector3(basis_y.x.x, 0, basis_y.x.z).normalized()
	var move := right * input.x + forward * -input.y
	if move.length() > 1.0:
		move = move.normalized()
	var running := Input.is_action_pressed("sprint")
	var speed := run_speed if running else walk_speed
	if move.length() > 0.05:
		facing = move.normalized()
	velocity.x = move.x * speed + knockback.x
	velocity.z = move.z * speed + knockback.z
	knockback = knockback.move_toward(Vector3.ZERO, 30.0 * delta)
	if not is_on_floor():
		velocity.y -= gravity * delta
	elif can_move and Input.is_action_just_pressed("jump"):
		velocity.y = jump_velocity
		jump_sound.play()
		_play("jump", jump_anim_speed, jump_anim_start)
	move_and_slide()
	model.rotation.y = lerp_angle(model.rotation.y, atan2(facing.x, facing.z), clampf(12.0 * delta, 0.0, 1.0))
	_update_animation(move, running)


func _update_animation(move: Vector3, running: bool) -> void:
	if dead or not hurt_timer.is_stopped():
		return
	if not is_on_floor():
		if _current_anim != "jump":
			_play("jump", jump_anim_speed, 0.45)
	elif move.length() > 0.1:
		_play("run" if running else "walk")
	else:
		_play("idle")


func _play(anim_name: String, speed: float = 1.0, from_time: float = 0.0) -> void:
	if anim_name == _current_anim and from_time == 0.0:
		return
	_current_anim = anim_name
	anim.play("luffy/" + anim_name, 0.15, speed)
	if from_time > 0.0:
		anim.seek(from_time, true)


## Called by Buggy when the punch connects.
func receive_hit(damage: float, from_pos: Vector3) -> void:
	if dead or not invulnerability_timer.is_stopped():
		return
	health = maxf(0.0, health - damage)
	health_changed.emit(health, max_health)
	var away := Vector3(global_position.x - from_pos.x, 0, global_position.z - from_pos.z)
	if away.length() < 0.05:
		away = -facing
	knockback = away.normalized() * knockback_force
	velocity.y = 3.5
	hurt_sound.play()
	_shake = 0.18
	invulnerability_timer.start()
	if health <= 0.0:
		dead = true
		_play("hurt")
		died.emit()
	else:
		hurt_timer.start()
		_current_anim = ""
		anim.play("luffy/hurt", 0.1)
