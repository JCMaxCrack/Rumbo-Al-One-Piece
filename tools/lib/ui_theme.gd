class_name UITheme
extends RefCounted
## Visual theme of the interface (navy blue and gold).

const GOLD := Color(0.93, 0.78, 0.42)
const TEXT := Color(0.96, 0.94, 0.88)
const DIM := Color(0.72, 0.74, 0.8)
const BG := Color(0.07, 0.1, 0.17, 0.92)


static func box(bg: Color, border: Color, width: int = 2, radius: int = 6, margin: int = 10) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(width)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(margin)
	return s


static func make() -> Theme:
	var t := Theme.new()
	t.default_font_size = 20
	t.set_stylebox("panel", "PanelContainer", box(BG, GOLD))
	t.set_stylebox("normal", "Button", box(Color(0.14, 0.2, 0.32), Color(0.4, 0.5, 0.65), 1, 5, 8))
	t.set_stylebox("hover", "Button", box(Color(0.22, 0.3, 0.46), GOLD, 1, 5, 8))
	t.set_stylebox("pressed", "Button", box(Color(0.35, 0.28, 0.12), GOLD, 1, 5, 8))
	t.set_stylebox("focus", "Button", box(Color(0, 0, 0, 0), GOLD, 2, 5, 8))
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", GOLD)
	t.set_color("font_focus_color", "Button", GOLD)
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.7))
	t.set_constant("shadow_offset_x", "Label", 2)
	t.set_constant("shadow_offset_y", "Label", 2)
	t.set_stylebox("background", "ProgressBar", box(Color(0.05, 0.05, 0.08, 0.85), Color(0.25, 0.25, 0.3), 1, 3, 0))
	return t


static func label(txt: String, size: int = 20, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func bar(color: Color, w: float, h: float) -> ProgressBar:
	var b := ProgressBar.new()
	b.show_percentage = false
	b.custom_minimum_size = Vector2(w, h)
	b.add_theme_stylebox_override("fill", box(color, Color(0, 0, 0, 0), 0, 3, 0))
	return b


static func place(c: Control, preset: int, left: float, top: float, right: float, bottom: float) -> void:
	c.set_anchors_preset(preset)
	c.offset_left = left
	c.offset_top = top
	c.offset_right = right
	c.offset_bottom = bottom
