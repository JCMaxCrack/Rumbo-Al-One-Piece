class_name Collectible
extends Area3D
## A piece of meat the player has to pick up (part of Koby's mission). It gives back part of Luffy's health.
## Nodes used (see scenes/items/meat.tscn): Visual, AnimationPlayer ("float"), PickupSound, CollisionShape3D.

signal collected(item: Collectible)

## Health that Luffy recovers when he eats this meat.
@export var heal_amount := 25.0

@onready var visual: Node3D = $Visual
@onready var pickup_sound: AudioStreamPlayer3D = $PickupSound

var taken := false


func _ready() -> void:
	add_to_group("minimap_meat")


func _on_body_entered(body: Node3D) -> void:
	if taken or not body is Player or (body as Player).dead:
		return
	taken = true
	(body as Player).heal(heal_amount)
	visual.visible = false
	set_deferred("monitoring", false)
	pickup_sound.play()
	collected.emit(self)


func _on_pickup_sound_finished() -> void:
	queue_free()
