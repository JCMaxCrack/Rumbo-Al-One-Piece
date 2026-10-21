class_name Player
extends CharacterBody3D
## Luffy: walk, sprint, jump, swim and the Gomu Gomu punch (stretching arm).
## Nodes used (see scenes/player/luffy.tscn):
##   Model (the luffy.fbx instance), AnimationPlayer (animations library "luffy"),
##   CameraPivot/SpringArm3D/Camera3D, PunchHitbox, HurtSound, JumpSound, SplashSound,
##   SwingSound, PunchSound, InvulnerabilityTimer, HurtTimer, AttackTimer.

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
@export_group("Swimming")
## Height of the sea surface (the Water node of the island).
@export var water_level := 0.0
@export var swim_speed := 3.0
@export var swim_sprint_speed := 4.8
## When the water is deeper than this (from the feet), Luffy starts swimming.
@export var swim_enter_depth := 1.15
## While swimming the feet float this far under the surface.
@export var swim_float_depth := 0.8
## Small jump to get out of the water onto low ground.
@export var swim_jump_velocity := 5.5
@export_group("Punch")
@export var punch_damage := 15.0
@export var punch_reach := 1.7
@export var attack_move_factor := 0.3

@onready var model: Node3D = $Model
@onready var anim: AnimationPlayer = $AnimationPlayer
@onready var camera_pivot: Node3D = $CameraPivot
@onready var spring_arm: SpringArm3D = $CameraPivot/SpringArm3D
@onready var camera: Camera3D = $CameraPivot/SpringArm3D/Camera3D
@onready var punch_hitbox: Area3D = $PunchHitbox
@onready var hurt_sound: AudioStreamPlayer3D = $HurtSound
@onready var jump_sound: AudioStreamPlayer3D = $JumpSound
@onready var splash_sound: AudioStreamPlayer3D = $SplashSound
@onready var swing_sound: AudioStreamPlayer3D = $SwingSound
@onready var punch_sound: AudioStreamPlayer3D = $PunchSound
@onready var invulnerability_timer: Timer = $InvulnerabilityTimer
@onready var hurt_timer: Timer = $HurtTimer
@onready var attack_timer: Timer = $AttackTimer

var health := 100.0
var facing := Vector3.FORWARD
var knockback := Vector3.ZERO
var dead := false
var swimming := false
var controls_enabled := true
var _current_anim := ""
var _current_speed := 1.0
var _shake := 0.0


func _ready() -> void:
	add_to_group("player")
	health = max_health
	health_changed.emit(health, max_health)
	_play("idle")


func _unhandled_input(event: InputEvent) -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseMotion:
		look((event as InputEventMouseMotion).relative)
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		attack()


## Rotates the camera (mouse, right stick or a finger on the touch screen).
func look(rel: Vector2) -> void:
	camera_pivot.rotation.y -= rel.x * mouse_sensitivity
	spring_arm.rotation.x = clampf(spring_arm.rotation.x - rel.y * mouse_sensitivity, -1.1, 0.35)


func _process(delta: float) -> void:
	var stick := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if stick.length() > 0.1:
		look(stick * 900.0 * delta)
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
	if can_move and Input.is_action_just_pressed("attack"):
		attack()
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back") if can_move else Vector2.ZERO
	var basis_y := camera_pivot.global_transform.basis
	var forward := Vector3(-basis_y.z.x, 0, -basis_y.z.z).normalized()
	var right := Vector3(basis_y.x.x, 0, basis_y.x.z).normalized()
	var move := right * input.x + forward * -input.y
	if move.length() > 1.0:
		move = move.normalized()
	var running := Input.is_action_pressed("sprint")
	_update_swimming()
	var speed := run_speed if running else walk_speed
	if swimming:
		speed = swim_sprint_speed if running else swim_speed
	if is_attacking():
		speed *= attack_move_factor
	if move.length() > 0.05 and not is_attacking():
		facing = move.normalized()
	velocity.x = move.x * speed + knockback.x
	velocity.z = move.z * speed + knockback.z
	knockback = knockback.move_toward(Vector3.ZERO, 30.0 * delta)
	var float_y := water_level - swim_float_depth
	if swimming and global_position.y <= float_y + 0.05:
		# buoyancy: the body floats with the head out of the water
		velocity.y = lerpf(velocity.y, (float_y - global_position.y) * 4.0, clampf(6.0 * delta, 0.0, 1.0))
		if can_move and Input.is_action_just_pressed("jump"):
			velocity.y = swim_jump_velocity
			splash_sound.play()
	elif not is_on_floor():
		velocity.y -= gravity * delta
	elif can_move and Input.is_action_just_pressed("jump"):
		velocity.y = jump_velocity
		jump_sound.play()
		_play("jump", jump_anim_speed, jump_anim_start)
	move_and_slide()
	model.rotation.y = lerp_angle(model.rotation.y, atan2(facing.x, facing.z), clampf(12.0 * delta, 0.0, 1.0))
	punch_hitbox.position = facing * punch_reach + Vector3(0, 1.1, 0)
	_update_animation(move, running)


func _update_swimming() -> void:
	var depth := water_level - global_position.y
	if not swimming and depth > swim_enter_depth:
		swimming = true
		velocity.y *= 0.25
		splash_sound.play()
		if is_attacking():
			attack_timer.stop()
	elif swimming and depth < swim_float_depth - 0.1 and is_on_floor():
		swimming = false


func is_attacking() -> bool:
	return not attack_timer.is_stopped()


## Gomu Gomu no... Pistol! The "attack" animation calls _on_punch_impact() when the arm is stretched.
func attack() -> void:
	if dead or swimming or is_attacking() or not controls_enabled or not hurt_timer.is_stopped():
		return
	attack_timer.start()
	swing_sound.play()
	_play("attack", 1.0, 0.0, true)


func _on_punch_impact() -> void:
	for body in punch_hitbox.get_overlapping_bodies():
		if body != self and body.has_method("receive_hit"):
			body.receive_hit(punch_damage, global_position)
			punch_sound.play()
			_shake = 0.08


func _update_animation(move: Vector3, running: bool) -> void:
	if dead or not hurt_timer.is_stopped() or is_attacking():
		return
	if swimming:
		var moving := move.length() > 0.1
		_play("swim", (1.25 if running else 1.0) if moving else 0.4)
	elif not is_on_floor():
		if _current_anim != "jump":
			_play("jump", jump_anim_speed, 0.45)
	elif move.length() > 0.1:
		_play("run" if running else "walk")
	else:
		_play("idle")


func _play(anim_name: String, speed: float = 1.0, from_time: float = 0.0, restart: bool = false) -> void:
	if anim_name == _current_anim and from_time == 0.0 and not restart:
		if not is_equal_approx(speed, _current_speed):
			_current_speed = speed
			anim.play("luffy/" + anim_name, 0.15, speed)
		return
	_current_anim = anim_name
	_current_speed = speed
	anim.play("luffy/" + anim_name, 0.15 if not restart else 0.05, speed)
	if from_time > 0.0:
		anim.seek(from_time, true)


## Every piece of meat gives back part of Luffy's health.
func heal(amount: float) -> void:
	if dead:
		return
	health = minf(max_health, health + amount)
	health_changed.emit(health, max_health)


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
	attack_timer.stop()
	if health <= 0.0:
		dead = true
		_play("hurt")
		died.emit()
	else:
		hurt_timer.start()
		_current_anim = ""
		anim.play("luffy/hurt", 0.1)
