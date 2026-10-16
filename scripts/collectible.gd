class_name Collectible
extends Area3D
## A piece of meat the player has to pick up (beta goal).
## Nodes used (see scenes/items/meat.tscn): Visual, AnimationPlayer ("float"), PickupSound, CollisionShape3D.

signal collected(item: Collectible)

@onready var visual: Node3D = $Visual
@onready var pickup_sound: AudioStreamPlayer3D = $PickupSound

var taken := false


func _on_body_entered(body: Node3D) -> void:
	if taken or not body is Player or (body as Player).dead:
		return
	taken = true
	visual.visible = false
	set_deferred("monitoring", false)
	pickup_sound.play()
	collected.emit(self)


func _on_pickup_sound_finished() -> void:
	queue_free()
