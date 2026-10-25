class_name Compass
extends Control
## Compass of the HUD (top of the screen): an arrow that points to the destination of the voyage,
## seen from the camera, with the name of the island and how far it is.

var angle := 0.0
var title := ""
var meters := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_target(a: float, name: String, dist: float) -> void:
	angle = a
	title = name
	meters = dist
	queue_redraw()


func _draw() -> void:
	var c := Vector2(size.x / 2.0, 34.0)
	var r := 28.0
	draw_circle(c, r + 4.0, Color(0.05, 0.07, 0.12, 0.8))
	draw_arc(c, r + 3.0, 0.0, TAU, 40, Color(0.93, 0.78, 0.42), 2.5, true)
	for i in 8:
		var a := i * PI / 4.0
		var l := 6.0 if i % 2 == 0 else 3.0
		var d := Vector2(sin(a), -cos(a))
		draw_line(c + d * (r - l), c + d * r, Color(0.93, 0.78, 0.42, 0.7), 1.5)
	var dir := Vector2(sin(angle), -cos(angle))
	var side := dir.orthogonal()
	var tip := c + dir * (r - 4.0)
	var back := c - dir * (r * 0.45)
	draw_colored_polygon(PackedVector2Array([tip, c + side * 9.0 - dir * 2.0, back, c - side * 9.0 - dir * 2.0]), Color(1.0, 0.82, 0.3))
	draw_polyline(PackedVector2Array([tip, c + side * 9.0 - dir * 2.0, back, c - side * 9.0 - dir * 2.0, tip]), Color(0.3, 0.15, 0.0), 1.5)
	var font := get_theme_default_font()
	var text := "%s  ·  %s" % [title, _distance_text()]
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	var box := Rect2(size.x / 2.0 - w / 2.0 - 10.0, 70.0, w + 20.0, 26.0)
	draw_rect(box, Color(0.05, 0.07, 0.12, 0.8))
	draw_string_outline(font, Vector2(box.position.x + 10.0, 89.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 3, Color(0, 0, 0))
	draw_string(font, Vector2(box.position.x + 10.0, 89.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1.0, 0.92, 0.7))


func _distance_text() -> String:
	if meters >= 1000.0:
		return "%.1f km" % (meters / 1000.0)
	return "%d m" % int(meters)
