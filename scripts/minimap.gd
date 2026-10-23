class_name Minimap
extends Control
## Mini map of the island (in the HUD). The picture is a top view of the island
## (assets/ui/minimap_island.png, 440 x 440 m); the rest is drawn every 0.1 s:
##   meat (orange), mini enemies (red), Buggy (big red), Going Merry (brown boat),
##   Koby and Zoro (blue), checkpoints (flag), Luffy (white arrow) and Zoro/player 2 (green arrow).
## North is up. Meat and the ship outside the visible area are drawn on the border, pointing to
## where they are. "map" (M / D-pad up) switches between the small map around the player and the
## whole island (big).
## The nodes are found by group: minimap_meat, enemies, minimap_ship, minimap_npc, checkpoints, players.

const COLORS := {
	"meat": Color(1.0, 0.6, 0.15), "enemy": Color(0.95, 0.2, 0.2), "boss": Color(0.8, 0.05, 0.1),
	"ship": Color(0.6, 0.38, 0.18), "npc": Color(0.35, 0.65, 1.0), "checkpoint": Color(1.0, 0.85, 0.25),
	"p1": Color(1, 1, 1), "p2": Color(0.45, 1.0, 0.45),
}
const LEGEND := [["meat", "Meat"], ["enemy", "Enemy"], ["boss", "Buggy"], ["ship", "Going Merry"], ["npc", "Koby / Zoro"], ["checkpoint", "Checkpoint"]]

@export var map_texture: Texture2D
@export var world_size := 440.0
## Meters from the player to the border of the small map.
@export var view_radius := 80.0
@export var big := false

var _small_rect := Rect2()
var _timer := 0.0


func _ready() -> void:
	_small_rect = Rect2(position, size)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func toggle_big() -> void:
	set_big(not big)


func set_big(on: bool) -> void:
	big = on
	if big:
		var vs := get_viewport_rect().size
		var side := minf(vs.x, vs.y) * 0.8
		set_anchors_preset(Control.PRESET_TOP_LEFT)
		position = (vs - Vector2(side, side)) / 2.0
		size = Vector2(side, side)
	else:
		set_anchors_preset(Control.PRESET_TOP_RIGHT)
		offset_left = -16.0 - _small_rect.size.x
		offset_right = -16.0
		offset_top = 16.0
		offset_bottom = 16.0 + _small_rect.size.y
	queue_redraw()


func _process(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		_timer = 0.1
		queue_redraw()


func _center() -> Vector3:
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return Vector3(world_size / 2.0, 0, world_size / 2.0)
	return (players[0] as Node3D).global_position


## World position -> point inside the map (and if it is inside the visible area).
func _to_map(p: Vector3, c: Vector3, radius: float) -> Array:
	var rel := Vector2(p.x - c.x, p.z - c.z) / radius
	var inside := absf(rel.x) <= 1.0 and absf(rel.y) <= 1.0
	var clamped := rel.limit_length(1.0) if not inside else rel
	if not inside:
		clamped = rel / maxf(absf(rel.x), absf(rel.y)) * 0.94
	return [size / 2.0 + clamped * size / 2.0, inside]


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, Color(0.07, 0.27, 0.45))
	var c := _center()
	var radius := view_radius
	if big:
		c = Vector3(world_size / 2.0, 0, world_size / 2.0)
		radius = world_size / 2.0
	if map_texture:
		var px := map_texture.get_width() / world_size
		var src := Rect2((c.x - radius) * px, (c.z - radius) * px, radius * 2.0 * px, radius * 2.0 * px)
		var tex_rect := Rect2(Vector2.ZERO, map_texture.get_size())
		var clip := src.intersection(tex_rect)
		if clip.has_area():
			var dst := Rect2((clip.position - src.position) / src.size * size, clip.size / src.size * size)
			draw_texture_rect_region(map_texture, dst, clip)
	var icon := 7.0 if big else 5.0
	for cp in get_tree().get_nodes_in_group("checkpoints"):
		var m: Array = _to_map((cp as Node3D).global_position, c, radius)
		if m[1]:
			_flag(m[0], icon, COLORS.checkpoint)
	var ship := get_tree().get_first_node_in_group("minimap_ship") as Node3D
	if ship:
		var ms: Array = _to_map(ship.global_position, c, radius)
		_boat(ms[0], icon * (1.6 if ms[1] else 1.2), COLORS.ship)
	for n in get_tree().get_nodes_in_group("minimap_npc"):
		var nn := n as Node3D
		if nn.is_visible_in_tree():
			var m2: Array = _to_map(nn.global_position, c, radius)
			if m2[1]:
				draw_circle(m2[0], icon * 0.9, COLORS.npc)
	for e in get_tree().get_nodes_in_group("enemies"):
		var en := e as Node3D
		if en.has_method("is_defeated") and en.is_defeated():
			continue
		var m3: Array = _to_map(en.global_position, c, radius)
		if not m3[1]:
			continue
		if en is BuggyBoss:
			draw_circle(m3[0], icon * 1.5, COLORS.boss)
			draw_circle(m3[0], icon * 0.6, Color.WHITE)
		else:
			draw_circle(m3[0], icon * 0.85, COLORS.enemy)
	for meat in get_tree().get_nodes_in_group("minimap_meat"):
		var mt := meat as Collectible
		if mt == null or mt.taken:
			continue
		var m4: Array = _to_map(mt.global_position, c, radius)
		var s := icon * (1.0 if m4[1] else 0.7)
		draw_colored_polygon(PackedVector2Array([m4[0] + Vector2(0, -s), m4[0] + Vector2(s, 0), m4[0] + Vector2(0, s), m4[0] + Vector2(-s, 0)]), COLORS.meat)
	for p in get_tree().get_nodes_in_group("players"):
		var pl := p as Player
		if pl == null or pl.control == Player.Controller.NONE:
			if pl and pl.is_visible_in_tree():
				var m5: Array = _to_map(pl.global_position, c, radius)
				if m5[1]:
					draw_circle(m5[0], icon * 0.9, COLORS.npc)
			continue
		var m6: Array = _to_map(pl.global_position, c, radius)
		_arrow(m6[0], pl.facing, icon * 1.6, COLORS.p1 if pl.control == Player.Controller.PLAYER_ONE else COLORS.p2)
	draw_rect(r, Color(0.93, 0.78, 0.42), false, 2.0)
	if big:
		var font := get_theme_default_font()
		var y := 12.0
		draw_rect(Rect2(6, 4, 170, LEGEND.size() * 20 + 30), Color(0, 0, 0, 0.55))
		for item in LEGEND:
			draw_circle(Vector2(18, y + 10), 5, COLORS[item[0]])
			draw_string(font, Vector2(30, y + 15), item[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
			y += 20.0
		draw_string(font, Vector2(14, y + 15), "M: close the map", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.8, 0.8, 0.8))


func _arrow(p: Vector2, dir: Vector3, s: float, col: Color) -> void:
	var a := atan2(dir.x, -dir.z)
	var pts := PackedVector2Array([Vector2(0, -s), Vector2(s * 0.7, s * 0.8), Vector2(0, s * 0.35), Vector2(-s * 0.7, s * 0.8)])
	for i in pts.size():
		pts[i] = p + pts[i].rotated(a)
	draw_colored_polygon(pts, col)
	draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0, 0, 0, 0.8), 1.5)


func _boat(p: Vector2, s: float, col: Color) -> void:
	draw_colored_polygon(PackedVector2Array([p + Vector2(-s, 0), p + Vector2(s, 0), p + Vector2(s * 0.6, s * 0.6), p + Vector2(-s * 0.6, s * 0.6)]), col)
	draw_line(p, p + Vector2(0, -s * 1.2), col, 2.0)
	draw_colored_polygon(PackedVector2Array([p + Vector2(0, -s * 1.2), p + Vector2(s * 0.8, -s * 0.4), p + Vector2(0, -s * 0.3)]), Color(0.95, 0.95, 0.9))


func _flag(p: Vector2, s: float, col: Color) -> void:
	draw_line(p + Vector2(0, s), p + Vector2(0, -s), Color(0.3, 0.2, 0.1), 1.5)
	draw_colored_polygon(PackedVector2Array([p + Vector2(0, -s), p + Vector2(s, -s * 0.6), p + Vector2(0, -s * 0.2)]), col)
