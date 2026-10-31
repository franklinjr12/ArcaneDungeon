extends RefCounted

func run(t) -> void:
	for scene_path in ["res://scenes/main.tscn", "res://scenes/sandbox.tscn", "res://scenes/arena.tscn"]:
		var scene = load(scene_path)
		t.check(scene is PackedScene, "scene loads: " + scene_path)
		if scene is PackedScene:
			var instance = scene.instantiate()
			t.check(instance != null, "scene instantiates: " + scene_path)
			instance.free()
	t.check(InputMap.has_action("move_up"), "movement input mapped")
	t.check(InputMap.has_action("dash"), "dash input mapped")
	t.check(InputMap.has_action("cast_slot_1"), "primary spell input mapped")
