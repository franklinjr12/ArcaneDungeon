extends RefCounted
## Visual styles derived from reference; reusable by all current game scenes.
const SkinA = preload("res://ui/skin_a.gd")
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
	t.set_stylebox("panel","PanelContainer",SkinA.stylebox("ad_ui_panel_large",12))
	for st in ["normal","hover","pressed","disabled","focus"]:
		t.set_stylebox(st,"Button",SkinA.stylebox("ad_ui_btn_"+st,6))
	t.set_stylebox("selected","Button",SkinA.stylebox("ad_ui_btn_selected",6))
	t.set_color("font_color","Button",SkinA.label_color("normal"))
	t.set_color("font_hover_color","Button",SkinA.label_color("hover"))
	t.set_color("font_pressed_color","Button",SkinA.label_color("pressed"))
	t.set_color("font_focus_color","Button",SkinA.label_color("focus"))
	t.set_color("font_disabled_color","Button",SkinA.label_color("disabled"))
	t.set_color("font_color","Label",SkinA.label_color("normal"))
	t.set_stylebox("normal","LineEdit",SkinA.stylebox("ad_ui_dropdown_normal",6))
	t.set_stylebox("focus","LineEdit",SkinA.stylebox("ad_ui_btn_focus",6))
	# Tabs
	for tb in ["TabBar","TabContainer"]:
		t.set_stylebox("tab_selected",tb,SkinA.stylebox("ad_ui_tab_active",6))
		t.set_stylebox("tab_unselected",tb,SkinA.stylebox("ad_ui_tab_inactive",6))
		t.set_stylebox("tab_hovered",tb,SkinA.stylebox("ad_ui_tab_hover",6))
		t.set_stylebox("tab_disabled",tb,SkinA.stylebox("ad_ui_tab_disabled",6))
		t.set_color("font_selected_color",tb,SkinA.label_color("selected"))
		t.set_color("font_unselected_color",tb,SkinA.label_color("normal"))
		t.set_color("font_hovered_color",tb,SkinA.label_color("hover"))
		t.set_color("font_disabled_color",tb,SkinA.label_color("disabled"))
	t.set_stylebox("panel","TabContainer",SkinA.stylebox("ad_ui_panel_large",12))
	# Sliders
	t.set_stylebox("slider","HSlider",SkinA.stylebox("ad_ui_slider_track",0))
	t.set_stylebox("grabber_area","HSlider",SkinA.stylebox("ad_ui_slider_fill",0))
	t.set_stylebox("grabber_area_highlight","HSlider",SkinA.stylebox("ad_ui_slider_fill",0))
	t.set_icon("grabber","HSlider",SkinA.region("ad_ui_slider_grab_normal"))
	t.set_icon("grabber_highlight","HSlider",SkinA.region("ad_ui_slider_grab_hover"))
	t.set_icon("grabber_disabled","HSlider",SkinA.region("ad_ui_slider_grab_disabled"))
	# Toggles
	for tg in ["CheckButton","CheckBox"]:
		t.set_stylebox("normal",tg,StyleBoxEmpty.new())
		t.set_icon("checked",tg,SkinA.region("ad_ui_toggle_on_normal"))
		t.set_icon("unchecked",tg,SkinA.region("ad_ui_toggle_off_normal"))
		t.set_icon("checked_disabled",tg,SkinA.region("ad_ui_toggle_on_disabled"))
		t.set_icon("unchecked_disabled",tg,SkinA.region("ad_ui_toggle_off_disabled"))
		t.set_color("font_color",tg,SkinA.label_color("normal"))
		t.set_color("font_hover_color",tg,SkinA.label_color("hover"))
		t.set_color("font_pressed_color",tg,SkinA.label_color("selected"))
		t.set_color("font_disabled_color",tg,SkinA.label_color("disabled"))
	# Dropdown
	t.set_stylebox("normal","OptionButton",SkinA.stylebox("ad_ui_dropdown_normal",6))
	t.set_stylebox("hover","OptionButton",SkinA.stylebox("ad_ui_dropdown_hover",6))
	t.set_stylebox("pressed","OptionButton",SkinA.stylebox("ad_ui_dropdown_open",6))
	t.set_stylebox("disabled","OptionButton",SkinA.stylebox("ad_ui_dropdown_disabled",6))
	t.set_stylebox("focus","OptionButton",SkinA.stylebox("ad_ui_btn_focus",6))
	t.set_color("font_color","OptionButton",SkinA.label_color("normal"))
	t.set_color("font_hover_color","OptionButton",SkinA.label_color("hover"))
	t.set_color("font_pressed_color","OptionButton",SkinA.label_color("pressed"))
	t.set_color("font_disabled_color","OptionButton",SkinA.label_color("disabled"))
	# Scroll
	t.set_stylebox("scroll","VScrollBar",SkinA.stylebox("ad_ui_scroll_track_v",0))
	t.set_stylebox("grabber","VScrollBar",SkinA.stylebox("ad_ui_scroll_thumb_v_normal",0))
	t.set_stylebox("grabber_highlight","VScrollBar",SkinA.stylebox("ad_ui_scroll_thumb_v_hover",0))
	t.set_stylebox("grabber_pressed","VScrollBar",SkinA.stylebox("ad_ui_scroll_thumb_v_pressed",0))
	return t

static func apply(root: Control) -> void:
	root.theme = make()
	root.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
