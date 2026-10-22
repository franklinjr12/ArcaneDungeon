extends "res://ui/combat_canvas.gd"
## M3 entrance, exit and reward markers over the proven M2 gameplay drawing.
var run_flow

func _draw() -> void:
	super._draw()
	if run_flow == null or run_flow.mode != "combat":
		return
	var offset := camera_offset()
	var entrance: Vector2 = run_flow.room.marker("entrance")-offset
	var departure: Vector2 = run_flow.room.marker("exit")-offset
	var gift: Vector2 = run_flow.room.marker("reward")-offset
	var open: bool = run_flow.state == "cleared"
	draw_arc(entrance,28,0,TAU,40,Color("#b5c4d7"),2)
	draw_arc(departure,31,0,TAU,42,Color("#81e2b8") if open else Color("#dc8498"),4)
	draw_string(ThemeDB.fallback_font,departure+Vector2(-28,-39),
		"EXIT OPEN" if open else "LOCKED",HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color.WHITE)
	if open and not run_flow.reward_collected and run_flow.room.values["type"] == "combat":
		draw_circle(gift,19,Color("#e6d591"))
		draw_arc(gift,23,0,TAU,32,Color.WHITE,2)
		draw_string(ThemeDB.fallback_font,gift+Vector2(-43,-35),"RUNE CHOICE",
			HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color.WHITE)
