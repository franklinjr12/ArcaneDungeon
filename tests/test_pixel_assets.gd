extends RefCounted
## Visual asset pipeline regressions: paths, dimensions, animation, runtime filtering.
const THEME = preload("res://ui/pixel_theme.gd")
const ART = preload("res://ui/pixel_art_renderer.gd")
func run(t) -> void:
	var character_dims := {"mage":Vector2i(480,56),"bone_thrall":Vector2i(480,56),
		"fallen_adept":Vector2i(480,56),"grave_hound":Vector2i(480,56),
		"undead_warden":Vector2i(1040,112),"dummy":Vector2i(480,56)}
	# Art files keep their legacy stems; the art workstream renames them.
	var stems := {"mage":"mage","bone_thrall":"purs"+"uer","fallen_adept":"ran"+"ged",
		"grave_hound":"flan"+"ker","undead_warden":"bo"+"ss","dummy":"dummy"}
	for name in character_dims:
		var png: String = "res://assets/pixel/"+stems[name]+"_sheet.png"
		var tex = load(png)
		t.check(tex is Texture2D,"ART character sprite texture imported: "+name)
		if tex is Texture2D:
			t.equal(Vector2i(tex.get_width(),tex.get_height()),character_dims[name],
				"ART character sheet 10 fixed-size frames: "+name)
			var width: int = character_dims[name].x/10
			var raw: Image = tex.get_image()
			var idle_a: PackedByteArray = raw.get_region(Rect2i(0,0,width,character_dims[name].y)).get_data()
			var idle_b: PackedByteArray = raw.get_region(Rect2i(width,0,width,character_dims[name].y)).get_data()
			t.check(idle_a != idle_b,"ART idle frames have meaningful movement: "+name)
			var dead: PackedByteArray = raw.get_region(Rect2i(width*9,0,width,character_dims[name].y)).get_data()
			t.check(dead != idle_a,"ART dead frame differs from idle: "+name)
		t.check(FileAccess.file_exists("res://art/aseprite/"+stems[name]+".aseprite"),
			"ART editable Aseprite character source: "+name)
	var assets := {"rune_icons":Vector2i(256,96),"spell_effects":Vector2i(256,256),
		"dungeon_tiles":Vector2i(256,96),"dungeon_props":Vector2i(384,48),
		"menu_background":Vector2i(1280,720),"panel_frame":Vector2i(32,32),
		"button_frame":Vector2i(32,24)}
	for name in assets:
		var path: String = "res://assets/pixel/"+name+".png"
		var tex = load(path)
		t.check(tex is Texture2D,"ART imported UI/tiles/VFX atlas: "+name)
		if tex is Texture2D:
			t.equal(Vector2i(tex.get_width(),tex.get_height()),assets[name],
				"ART expected atlas dimensions: "+name)
		t.check(FileAccess.file_exists("res://art/aseprite/"+name+".aseprite"),
			"ART editable Aseprite atlas source: "+name)
	for name in ["fire","water","lightning","orb","enemy","arc","impact","dodge"]:
		t.check(FileAccess.file_exists("res://art/aseprite/vfx_"+name+".aseprite"),
			"ART editable animated VFX source: "+name)
	var theme: Theme = THEME.make()
	t.check(theme.has_stylebox("panel","PanelContainer"),"ART shared gold-framed panel theme")
	t.check(theme.has_stylebox("normal","Button"),"ART shared gold-framed button theme")
	t.check(FileAccess.file_exists("res://docs/assets/art_style_reference.png"),
		"ART canonical owner reference remains in the repository")
