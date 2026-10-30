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
	arena._click(Vector2(385,450),MOUSE_BUTTON_LEFT)
	arena._physics_process(1.0/60.0)
	verify(arena.session.player.casts == 1,"left click executes compiled spell")
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
	quit(1 if failed > 0 else 0)
