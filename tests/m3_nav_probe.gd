extends SceneTree
const Geometry = preload("res://world/arena_geometry.gd")
func _initialize() -> void:
	call_deferred("_test")
func _test() -> void:
	var config = JSON.parse_string(FileAccess.get_file_as_string("res://combat/combat_tuning_v1.json"))
	var geo = Geometry.new(config["arena"])
	for origin in [Vector2(185,450),Vector2(340,450),Vector2(700,450),Vector2(1020,200),Vector2(400,600),Vector2(1298,882),Vector2(1220,700),Vector2(1298,300)]:
		var pos: Vector2 = origin
		var last: Vector2 = pos
		for i in 1300:
			var dir: Vector2 = geo.navigate_direction(pos,Vector2(1220,450),17)
			pos = geo.move_body(pos,dir*255.0/60.0,17)
			if i%140 == 0:
				print("PATH:",origin," step=",i," at=",pos," dir=",dir)
			if pos.distance_to(Vector2(1220,450))<65:
				print("PATH_SUCCESS:",origin," ticks=",i)
				break
		print("PATH_END:",origin," at=",pos)
	quit()
