extends RefCounted
## AD-152: skin A kit loader, layouts and theme.
const SkinA = preload("res://ui/skin_a.gd")
const SCREENS := ["menu", "pause", "settings_audio", "settings_video", "settings_controls", "settings_access"]

func run(t) -> void:
	t.check(SkinA.kit().get("sprites", {}).size() == 118, "AD-152 kit has 118 sprites")
	for screen in SCREENS:
		var l := SkinA.layout(screen)
		t.check(l.has("widgets") and l.has("canvas") and l.has("safe_area") and l.has("focus_order"), "AD-152 %s layout keys" % screen)
		var bad := 0
		var outside := 0
		for w in l.get("widgets", []):
			var sp := str(w.get("sprite", ""))
			if sp != "" and sp != "ad_key_logo" and not SkinA.has_sprite(sp):
				bad += 1
			if w.x < 0 or w.y < 0 or w.x + w.w > SkinA.CANVAS.x or w.y + w.h > SkinA.CANVAS.y:
				outside += 1
		t.equal(bad, 0, "AD-152 %s sprites resolve" % screen)
		t.equal(outside, 0, "AD-152 %s widgets inside canvas" % screen)
	t.equal(SkinA.resolve("ad_ui_modal_backdrop_25"), "ad_ui_modal_backdrop_50", "AD-152 pause backdrop remap")
	t.check(SkinA.has_sprite("ad_ui_modal_backdrop_25"), "AD-152 remapped backdrop exists")
	var sb := SkinA.stylebox("ad_ui_panel_large")
	t.check(sb.texture_margin_left == 12 and sb.texture_margin_top == 12 and sb.texture_margin_right == 12 and sb.texture_margin_bottom == 12, "AD-152 panel_large margins 12")
	t.equal(SkinA.canvas_scale(Vector2(1280, 720)), 2.0, "AD-152 canvas scale at 1280x720")
	t.equal(SkinA.canvas_origin(Vector2(1280, 720), 2.0), Vector2.ZERO, "AD-152 canvas origin")
