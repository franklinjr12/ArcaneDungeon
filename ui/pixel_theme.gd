extends RefCounted
## Visual styles derived from reference; reusable by all current game scenes.
const PANEL_TEXTURE = preload("res://assets/pixel/panel_frame.png")
const BUTTON_TEXTURE = preload("res://assets/pixel/button_frame.png")

static func _framed(texture: Texture2D, left: float = 8.0) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = texture
	style.texture_margin_left = left
	style.texture_margin_right = left
	style.texture_margin_top = left
	style.texture_margin_bottom = left
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style

static func _button(color: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.border_color = Color("#ac7a3a")
	s.set_border_width_all(2)
	s.set_corner_radius_all(2)
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 7
	s.content_margin_bottom = 7
	return s

static func make() -> Theme:
	var t := Theme.new()
	t.set_stylebox("panel","PanelContainer",_framed(PANEL_TEXTURE,8))
	t.set_stylebox("normal","Button",_framed(BUTTON_TEXTURE,7))
	t.set_stylebox("hover","Button",_button(Color("#25383d")))
	t.set_stylebox("pressed","Button",_button(Color("#56412d")))
	t.set_stylebox("focus","Button",_button(Color("#26393d")))
	t.set_stylebox("disabled","Button",_button(Color("#151d23")))
	t.set_color("font_color","Button",Color("#f1d4a0"))
	t.set_color("font_hover_color","Button",Color("#fff4cd"))
	t.set_color("font_pressed_color","Button",Color("#fff7cf"))
	t.set_color("font_disabled_color","Button",Color("#7b755f"))
	t.set_color("font_color","Label",Color("#e0cfaf"))
	t.set_stylebox("normal","LineEdit",_button(Color("#111b26")))
	t.set_stylebox("normal","OptionButton",_button(Color("#182630")))
	t.set_stylebox("hover","OptionButton",_button(Color("#263e42")))
	t.set_stylebox("pressed","OptionButton",_button(Color("#403729")))
	t.set_stylebox("normal","CheckBox",StyleBoxEmpty.new())
	t.set_color("font_color","CheckBox",Color("#e4cf9d"))
	t.set_color("font_color","OptionButton",Color("#e7ce98"))
	return t

static func apply(root: Control) -> void:
	root.theme = make()
	root.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
