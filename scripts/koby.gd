class_name Koby
extends StaticBody3D
## Koby (NPC). He only gives Luffy his mission: defeat Buggy and collect all the meat.
## The dialogue itself is shown by the HUD; game_world.gd decides what Koby says.
## Nodes used (see scenes/npcs/koby.tscn): Model (the koby.fbx instance), AnimationPlayer
## (library "koby": idle, wave), TalkArea, NameLabel, PromptLabel, MissionMarker.

signal player_nearby_changed(near: bool)

## Lines Koby says when he gives the mission.
@export_multiline var mission_lines: PackedStringArray = [
	"¡Luffy-chan! ¡I'm so glad you are here!",
	"Buggy the clown is hiding in the crater of the volcano, in the center of the island and he has everyone terrified.",
	"Your mission: Defeat Buggy and collect all the meat scattered around the island!",
	"Each pice of meat restores your health. And the Going Merry is anchored in the northeast port: go up the bridge on the av.",
]

@onready var model: Node3D = $Model
@onready var anim: AnimationPlayer = $AnimationPlayer
@onready var prompt_label: Label3D = $PromptLabel
@onready var mission_marker: Label3D = $MissionMarker

var player_near := false
var _player: Node3D


func _ready() -> void:
	add_to_group("minimap_npc")


func _on_talk_area_body_entered(body: Node3D) -> void:
	if body is Player:
		_player = body
		player_near = true
		prompt_label.visible = true
		anim.play("koby/wave", 0.3)
		player_nearby_changed.emit(true)


func _on_talk_area_body_exited(body: Node3D) -> void:
	if body is Player:
		player_near = false
		prompt_label.visible = false
		anim.play("koby/idle", 0.4)
		player_nearby_changed.emit(false)


func set_mission_given(given: bool) -> void:
	mission_marker.visible = not given


func set_prompt(text: String) -> void:
	prompt_label.text = text


func _process(delta: float) -> void:
	# Koby turns to look at Luffy while he is close
	if player_near and is_instance_valid(_player):
		var to := _player.global_position - global_position
		var target := atan2(to.x, to.z) - rotation.y
		model.rotation.y = lerp_angle(model.rotation.y, target, clampf(5.0 * delta, 0.0, 1.0))
