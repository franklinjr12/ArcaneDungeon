extends SceneTree
## End-to-end playable M2 arena scene and controller exercise.
var failed := 0
func _initialize() -> void:
	call_deferred("_run")

func verify(success: bool, what: String) -> void:
	if success:
		print("M2 UI PASS: ",what)
	else:
		failed += 1
		printerr("M2 UI FAIL: ",what)

func _run() -> void:
	var prefab = load("res://scenes/arena.tscn")
	verify(prefab is PackedScene,"combat arena scene loads")
	if not prefab is PackedScene:
		quit(1)
		return
	var arena = prefab.instantiate()
	root.add_child(arena)
	current_scene = arena
	await process_frame
	verify(arena.session != null and arena.session.initialized,"M2 gameplay session initialized")
	if arena.session == null:
		quit(1)
		return
	verify(arena.canvas != null,"arena canvas and camera created")
	verify(arena.session.alive_enemies() == 1,"single pursuer scenario ready")
	verify(arena.hud.text.contains("HP") and arena.hud.text.contains("SLOT 1"),"HP mana cooldown and slots visible")
	_check_slot_hud(arena.canvas.slot_hud,"arena")
	arena._click(Vector2(385,450),MOUSE_BUTTON_LEFT)
	arena._physics_process(1.0/60.0)
	verify(arena.session.player.casts == 1,"left click executes compiled spell")
	var hud = arena.canvas.slot_hud
	var bolt: Dictionary = hud.slot_view(0)
	verify(bolt["cooldown_left"] > 0 and bolt["state"] == "cooldown" and bolt["cooldown_fraction"] > 0.0,
		"slot 1 cooldown sweep after cast")
	arena.session.sim.mana = 0.0
	verify(hud.slot_view(1)["state"] == "no_mana" and not hud.slot_view(1)["affordable"],"not enough mana state on slot 2")
	verify(hud.slot_view(3)["state"] == "empty" and hud.slot_view(3)["affordable"],"empty slot ignores mana")
	arena.session.player.dash_cooldown = 10
	verify(not hud.dash_view()["ready"] and hud.dash_view()["cooldown_fraction"] > 0.0,"dash marker shows cooldown")
	arena.canvas.queue_redraw()
	hud.queue_redraw()
	await process_frame
	arena._command("debug")
	verify(arena.canvas.show_debug,"debug overlays toggle")
	arena._command("flash")
	verify(arena.session.reduce_flashes,"low-flash accessibility toggle")
	arena._command("pause")
	var before: int = arena.session.sim.clock.tick
	arena._physics_process(1.0/60.0)
	verify(arena.session.sim.clock.tick == before,"pause freezes arena simulation")
	arena._command("pause")
	arena._choose_scenario("mixed")
	verify(arena.session.alive_enemies() == 3,"mixed scenario button spawns three archetypes")
	verify(arena.session.player.casts == 0,"scenario reset clears prior casts")
	arena._command("loadout")
	verify(arena.starter == 1,"loadout button switches two starter formulas")
	verify(arena.session.sim.loadout.preview(1)["formula_id"] != "sample.fire_shot","loadout switch updates equipped slot")
	var caster = arena.session.sim.actor
	var source = arena.session.enemies[0].target
	arena.session.damage_player(source.id,999,"physical")
	arena.session.step()
	verify(arena.session.state == "dead","combat scene enters death state")
	arena._click(Vector2(400,450),MOUSE_BUTTON_LEFT)
	verify(arena.pending_cast == -1,"dead scene refuses cast click")
	arena._command("retry")
	verify(arena.session.state == "playing" and arena.session.sim.clock.tick == 0,"retry recreates clean arena")
	verify(arena.session.sim.queue.active_effect_count() == 0,"retry removes active spells")
	_check_slot_hud(arena.canvas.slot_hud,"arena after retry")
	arena.queue_free()
	await process_frame
	var run = load("res://scenes/run.tscn").instantiate()
	root.add_child(run)
	current_scene = run
	await process_frame
	verify(run.arena_canvas != null and run.arena_canvas.slot_hud != null,"run scene canvas hosts slot HUD")
	if run.arena_canvas != null and run.arena_canvas.slot_hud != null:
		_check_slot_hud(run.arena_canvas.slot_hud,"run")
	quit(1 if failed > 0 else 0)

func _check_slot_hud(hud, where: String) -> void:
	verify(hud.canvas != null and hud.slot_count() == 4,where+": 4 slot widgets")
	var labels: Array = []
	for i in hud.slot_count():
		labels.append(hud.slot_view(i)["key_label"])
	verify(labels == ["LMB","RMB","Q","E"],where+": keycap labels LMB RMB Q E")
	verify(hud.slot_view(0)["locked"] and not hud.slot_view(0)["empty"] and hud.slot_view(0)["mana_cost"] > 0,
		where+": slot 1 locked basic bolt with mana cost")
	verify(not hud.slot_view(1)["locked"] and hud.slot_view(1)["mana_cost"] > 0,where+": slot 2 unlocked with mana cost")
	verify(hud.slot_view(3)["empty"] and hud.slot_view(3)["state"] == "empty",where+": slot 4 visibly empty")
	verify(hud.slot_view(4).is_empty(),where+": no widget beyond slot 4")
	verify(hud.dash_view().has("ready") and hud.dash_view()["ready"],where+": dash marker ready")
