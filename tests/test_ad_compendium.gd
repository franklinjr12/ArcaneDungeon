extends RefCounted
## AD-153: skin A Compendium tabs, cell bounds at 1280x720, keyboard tab switching and paging.
const Screen = preload("res://ui/compendium_screen.gd")
const SkinA = preload("res://ui/skin_a.gd")

func run(t) -> void:
	var root = (Engine.get_main_loop() as SceneTree).root
	var old_size: Vector2i = root.size
	root.size = Vector2i(1280, 720)
	var screen = Screen.new()
	root.add_child(screen)
	var vp: Vector2 = screen.get_viewport_rect().size
	t.equal(vp, Vector2(1280, 720), "AD-153 compendium viewport 1280x720")
	var cats := Screen.catalogs_by_category()
	for tab in Screen.TABS:
		screen.select_tab(tab)
		var shown := []
		for other in screen.tab_pages:
			if screen.tab_pages[other].visible:
				shown.append(other)
		t.equal(shown, [tab], "AD-153 compendium %s tab shows only its page" % tab)
		t.check(screen.tab_buttons[tab].active, "AD-153 compendium %s tab active" % tab)
		var layout_cells := 0
		var prefix: String = {"runes": "rune_", "reactions": "reaction_", "enemies": "enemy_", "artifacts": "artifact_"}[tab]
		for id in SkinA.widgets_by_id("compendium_" + tab):
			if str(id).begins_with(prefix):
				layout_cells += 1
		t.equal(screen.cells[tab].size(), layout_cells, "AD-153 compendium %s builds every layout cell" % tab)
		var visible_cells := 0
		var inside := true
		for c in screen.cells[tab]:
			if not c.visible:
				continue
			visible_cells += 1
			var r := Rect2(c.position, c.size)
			inside = inside and Rect2(Vector2.ZERO, vp).encloses(r)
		t.equal(visible_cells, mini(layout_cells, cats[tab].size()), "AD-153 compendium %s visible cells" % tab)
		t.check(inside, "AD-153 compendium %s cells inside the viewport" % tab)
	t.equal(screen.page_count("enemies"), 2, "AD-153 compendium enemies page (14 cells, 17 entries)")
	screen.select_tab("enemies")
	screen._page_step("enemies", 1)
	t.equal(screen.entries("enemies").size(), 3, "AD-153 compendium enemies page 2 has the remainder")
	screen._page_step("enemies", -1)
	var ev := InputEventKey.new()
	ev.pressed = true
	ev.physical_keycode = KEY_E
	screen._unhandled_input(ev)
	t.equal(screen.current_tab, "artifacts", "AD-153 compendium E steps to next tab")
	ev.physical_keycode = KEY_Q
	screen._unhandled_input(ev)
	screen._unhandled_input(ev)
	t.equal(screen.current_tab, "reactions", "AD-153 compendium Q steps back")
	var hits := []
	screen.back_requested.connect(func(): hits.append(1))
	screen.back_button.pressed.emit()
	t.equal(hits.size(), 1, "AD-153 compendium back emits back_requested")
	screen.free()
	root.size = old_size
