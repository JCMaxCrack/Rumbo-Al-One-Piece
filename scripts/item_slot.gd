class_name ItemSlot
extends Control
## One slot of the inventory in the HUD: a drawn icon of the item, how many there are, the number
## of the key that selects it and a golden border when it is the selected one.

@export var slot_number := 1

var item_id := ""
var count := 0
var selected := false


func set_item(id: String, amount: int, is_selected: bool) -> void:
	item_id = id
	count = amount
	selected = is_selected
	tooltip_text = GameState.item_name(id)
	queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, Color(0, 0, 0, 0.55))
	draw_rect(r, Color(1.0, 0.82, 0.3) if selected else Color(0.6, 0.55, 0.45, 0.8), false, 3.0 if selected else 1.5)
	var c := size / 2.0
	var s := minf(size.x, size.y) * 0.32
	match item_id:
		"meat":
			draw_line(c + Vector2(s * 0.2, s * 0.2), c + Vector2(s * 0.95, s * 0.95), Color(0.95, 0.92, 0.85), s * 0.28)
			draw_circle(c + Vector2(s * 0.95, s * 0.95), s * 0.2, Color(0.95, 0.92, 0.85))
			draw_circle(c + Vector2(-s * 0.15, -s * 0.15), s * 0.75, Color(0.62, 0.28, 0.12))
			draw_circle(c + Vector2(-s * 0.3, -s * 0.35), s * 0.3, Color(0.82, 0.45, 0.2))
		"orange":
			draw_circle(c + Vector2(0, s * 0.1), s * 0.8, Color(1.0, 0.58, 0.1))
			draw_circle(c + Vector2(-s * 0.25, -s * 0.15), s * 0.22, Color(1.0, 0.78, 0.4))
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -s * 0.7), c + Vector2(s * 0.6, -s * 1.0), c + Vector2(s * 0.2, -s * 0.55)]), Color(0.3, 0.7, 0.25))
		"key":
			draw_arc(c + Vector2(-s * 0.4, 0), s * 0.4, 0, TAU, 20, Color(0.95, 0.8, 0.3), s * 0.18)
			draw_line(c, c + Vector2(s * 1.0, 0), Color(0.95, 0.8, 0.3), s * 0.18)
			draw_line(c + Vector2(s * 0.75, 0), c + Vector2(s * 0.75, s * 0.4), Color(0.95, 0.8, 0.3), s * 0.15)
	var font := get_theme_default_font()
	draw_string(font, Vector2(4, 14), str(slot_number), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.8, 0.8, 0.8))
	if count > 1:
		draw_string(font, Vector2(size.x - 22, size.y - 5), "x%d" % count, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
