extends "res://ui/combat_canvas.gd"
## M3 entrance, exit and reward markers over the proven M2 gameplay drawing.
const Hud = preload("res://ui/pixel_hud.gd")
var run_flow
var _was_cleared := false
var _clear_tick := -1000

func _draw() -> void:
	super._draw()
	if run_flow == null or run_flow.mode != "combat":
		return
	var offset := camera_offset()
	var entrance: Vector2 = run_flow.room.marker("entrance")-offset
	var departure: Vector2 = run_flow.room.marker("exit")-offset
	var gift: Vector2 = run_flow.room.marker("reward")-offset
	var open: bool = run_flow.state == "cleared"
	var now: int = session.sim.clock.tick
	if open and not _was_cleared:
		_clear_tick = now
	_was_cleared = open
	if now >= _clear_tick and not Art.fx_frame("room.clear",now-_clear_tick).get("done",true):
		Art.draw_fx(self,"room.clear",size/2.0,now-_clear_tick)
	draw_arc(entrance,30,0,TAU,40,Color("#9b855c",0.65),2)
	Art.portal(self,departure,open,session.sim.clock.tick)
	draw_string(ThemeDB.fallback_font,departure+Vector2(-28,-39),
		"EXIT OPEN" if open else "LOCKED",HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color.WHITE)
	if open and not run_flow.reward_collected and run_flow.room.values["type"] == "combat":
		draw_texture_rect(Hud.ui_icon_texture("upgrade"),Rect2(gift-Vector2(16,16),Vector2(32,32)),false)
		draw_arc(gift,24,0,TAU,32,Color("#f6c46d"),2)
		draw_string(ThemeDB.fallback_font,gift+Vector2(-43,-35),"RUNE CHOICE",
			HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color.WHITE)
