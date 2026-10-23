class_name CompanionAI
extends Node
## Brain of a crew member that plays by himself (Zoro in single player, after he joins).
## It is a child node of the character (a Player with control = AI) and writes its ai_* inputs:
##   - if an enemy (group "enemies") is close to him and to the leader, he goes to fight it;
##   - otherwise he follows the leader, running when he is far;
##   - if he is stuck in front of something, he jumps; if he is very far, he appears next to the
##     leader (for example after Luffy sails, swims far or a checkpoint is loaded).

@export var leader: Node3D
@export var follow_distance := 3.5
@export var run_distance := 9.0
@export var teleport_distance := 45.0
@export var fight_radius := 10.0
@export var attack_range := 1.9

var _body: Player
var _stuck := 0.0
var _last := Vector3.ZERO
var _running := false
var _following := false


func _ready() -> void:
	_body = get_parent() as Player


func _physics_process(delta: float) -> void:
	if _body == null or leader == null or _body.control != Player.Controller.AI or _body.dead:
		return
	var me := _body.global_position
	var to_leader := leader.global_position - me
	to_leader.y = 0.0
	if to_leader.length() > teleport_distance:
		_body.global_position = leader.global_position - _leader_forward() * 2.5 + Vector3(0, 0.5, 0)
		_body.velocity = Vector3.ZERO
		return
	var enemy := _closest_enemy()
	var goal := Vector3.ZERO
	if enemy:
		var to_enemy := enemy.global_position - me
		to_enemy.y = 0.0
		if to_enemy.length() <= attack_range:
			_body.facing = to_enemy.normalized()
			_body.ai_attack = true
		else:
			goal = to_enemy
		_running = _hysteresis(_running, to_enemy.length(), 4.0, 2.5)
		_body.ai_run = _running
	else:
		# Starts following / running at the far distance but only stops when he is really close,
		# so the walk and run animations do not restart at the limit.
		var d := to_leader.length()
		_following = _hysteresis(_following, d, follow_distance, follow_distance - 1.2)
		_running = _hysteresis(_running, d, run_distance, follow_distance) and _following
		if _following:
			goal = to_leader
		_body.ai_run = _running
	_body.ai_move = goal.normalized() if goal.length() > 0.3 else Vector3.ZERO
	# stuck against a rock or a wall: jump
	var moved := Vector2(me.x - _last.x, me.z - _last.z).length()
	_last = me
	if _body.ai_move.length() > 0.5 and moved < 0.01 and _body.is_on_floor():
		_stuck += delta
		if _stuck > 0.4:
			_body.ai_jump = true
			_stuck = 0.0
	else:
		_stuck = 0.0


## On when value goes above `on_above`, off again only below `off_below`.
func _hysteresis(state: bool, value: float, on_above: float, off_below: float) -> bool:
	if state:
		return value > off_below
	return value > on_above


func _leader_forward() -> Vector3:
	var p := leader as Player
	return p.facing if p else Vector3.FORWARD


func _closest_enemy() -> Node3D:
	var best: Node3D = null
	var best_d := fight_radius
	for e in get_tree().get_nodes_in_group("enemies"):
		var n := e as Node3D
		if n == null or not n.is_inside_tree() or (n.has_method("is_defeated") and n.is_defeated()):
			continue
		var d := n.global_position.distance_to(_body.global_position)
		if d < best_d and n.global_position.distance_to(leader.global_position) < fight_radius * 1.6:
			best = n
			best_d = d
	return best
