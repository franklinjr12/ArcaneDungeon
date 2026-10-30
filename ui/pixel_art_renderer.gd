extends RefCounted
## Presentation only: the reference-matched pixel assets never own collision, damage or spells.
const TILE = preload("res://assets/pixel/dungeon_tiles.png")
const PROPS = preload("res://assets/pixel/dungeon_props.png")
const ICON = preload("res://assets/pixel/rune_icons.png")
const FX = preload("res://assets/pixel/spell_effects.png")
const MAGE = preload("res://assets/pixel/mage_sheet.png")
const PURSUER = preload("res://assets/pixel/pursuer_sheet.png")
const RANGED = preload("res://assets/pixel/ranged_sheet.png")
const FLANKER = preload("res://assets/pixel/flanker_sheet.png")
const BOSS = preload("res://assets/pixel/boss_sheet.png")
const DUMMY = preload("res://assets/pixel/dummy_sheet.png")
const ICONS = ["fire","water","lightning","projectile","burst","orb","homing","split","pierce","on_hit",
	"health","mana","rune","coin","dodge","wet","burning","charged","damage","door","shop","book","staff","shield"]
const EFFECT_ROWS = ["fire","water","lightning","orb","enemy","arc","impact","dodge"]
const F = {"mage":MAGE,"bone_thrall":PURSUER,"fallen_adept":RANGED,"grave_hound":FLANKER,"undead_warden":BOSS,"dummy":DUMMY}

static func tile_floor(canvas: CanvasItem, view: Rect2, offset: Vector2, stage: int = 0) -> void:
	canvas.draw_rect(Rect2(Vector2.ZERO,view.size),Color("#0f1924"))
	var max_x := int(ceil(view.size.x/32))+3
	var max_y := int(ceil(view.size.y/32))+3
	var first_x := int(floor(offset.x/32))
	var first_y := int(floor(offset.y/32))
	for ay in max_y:
		var gy := first_y+ay
		for ax in max_x:
			var gx := first_x+ax
			var h: int = (gx*73856093 ^ gy*19349663 ^ stage*83492791) & 0x7fffffff
			var variant: int = (16+h%8) if stage > 0 else h%8
			var pos := Vector2(float(gx*32),float(gy*32))-offset
			canvas.draw_texture_rect_region(TILE,Rect2(pos,Vector2(32,32)),
				Rect2(Vector2((variant%8)*32,(variant/8)*32),Vector2(32,32)))
	# Avoid bright grid: reference is continuous carved flagstones.

static func decorations(canvas: CanvasItem, offset: Vector2, stage: int = 0) -> void:
	# Decorative-only; never implicitly introduces a collectible or solid obstacle.
	var placements := [
		[Vector2(108,104),3],[Vector2(304,105),2],[Vector2(746,124),7],
		[Vector2(1030,115),4],[Vector2(1224,120),6],[Vector2(99,728),1],
		[Vector2(405,770),0],[Vector2(735,789),2],[Vector2(1110,750),6],
		[Vector2(1260,761),5],[Vector2(826,285),2],[Vector2(754,670),3]]
	for entry in placements:
		var at: Vector2 = entry[0]-offset
		if at.x < -60 or at.y < -60 or at.x > 1200 or at.y > 800:
			continue
		var n: int = int(entry[1])
		if stage > 0 and n in [2,3]:
			n = 6
		canvas.draw_texture_rect_region(PROPS,Rect2(at-Vector2(24,35),Vector2(48,48)),
			Rect2(Vector2(n*48,0),Vector2(48,48)))

static func walls(canvas: CanvasItem, wall_rects: Array, offset: Vector2) -> void:
	for wall in wall_rects:
		canvas.draw_rect(Rect2(wall.position-offset-Vector2(4,7),wall.size+Vector2(8,14)),Color("#0b1218",0.84))
		for y in range(0,int(wall.size.y),32):
			for x in range(0,int(wall.size.x),32):
				var p: Vector2 = wall.position+Vector2(x,y)-offset
				var dim := Vector2(minf(32,wall.size.x-x),minf(32,wall.size.y-y))
				var tile: int = 8+((x/32+y/32)%8)
				canvas.draw_texture_rect_region(TILE,Rect2(p,dim),
					Rect2(Vector2((tile%8)*32,32),dim))
		canvas.draw_rect(Rect2(wall.position-offset,wall.size),Color("#bf8a47"),false,2)
		canvas.draw_line(wall.position-offset+Vector2(3,4),wall.position-offset+Vector2(wall.size.x-3,4),Color("#dcb773",0.7),1)

static func entity(canvas: CanvasItem, kind: String, at: Vector2, tick: int, motion: Vector2 = Vector2.ZERO,
		casting: bool = false, hurt: bool = false, dead: bool = false) -> void:
	if not F.has(kind):
		kind = "dummy"
	var size: Vector2 = Vector2(104,112) if kind == "undead_warden" else Vector2(48,56)
	var frame := 0
	if dead:
		frame = 9
	elif hurt:
		frame = 8
	elif casting:
		frame = 6+((tick/5)%2)
	elif motion.length_squared() > 3.0:
		frame = 2+((tick/6)%4)
	else:
		frame = (tick/18)%2
	var where := Rect2(at+Vector2(-size.x/2,-size.y+7),size)
	canvas.draw_texture_rect_region(F[kind],where,Rect2(Vector2(frame*size.x,0),size))

static func icon(canvas: CanvasItem, name: String, at: Vector2, dimensions: Vector2 = Vector2(32,32)) -> void:
	var index: int = ICONS.find(name)
	if index == -1:
		index = 12
	canvas.draw_texture_rect_region(ICON,Rect2(at,dimensions),
		Rect2(Vector2(index%8*32,(index/8)*32),Vector2(32,32)))

static func effect(canvas: CanvasItem, kind: String, center: Vector2, tick: int,
		dimensions: Vector2 = Vector2(32,32), alpha: float = 1.0) -> void:
	var row: int = EFFECT_ROWS.find(kind)
	if row == -1:
		row = 6
	var frame: int = (tick/4)%8
	canvas.draw_texture_rect_region(FX,Rect2(center-dimensions/2.0,dimensions),
		Rect2(Vector2(frame*32,row*32),Vector2(32,32)),Color(1,1,1,clampf(alpha,0,1)))

static func status_icons(canvas: CanvasItem, target, tick: int, at: Vector2) -> void:
	var current: Dictionary = target.status.snapshot(tick)
	var i := 0
	for status_id in ["burning","wet","charged"]:
		if current.has(status_id):
			icon(canvas,status_id,at+Vector2(i*16,0),Vector2(17,17))
			i += 1

static func portal(canvas: CanvasItem, at: Vector2, open: bool, tick: int) -> void:
	var shade := Color("#5edfc3") if open else Color("#bd5366")
	canvas.draw_arc(at,27,PI,TAU,16,Color("#0d1823"),9)
	canvas.draw_arc(at,26,PI,TAU,16,Color("#a77c43"),6)
	canvas.draw_arc(at,21,PI,TAU,16,shade,2)
	canvas.draw_line(at+Vector2(-22,0),at+Vector2(-22,24),Color("#846037"),6)
	canvas.draw_line(at+Vector2(22,0),at+Vector2(22,24),Color("#846037"),6)
	icon(canvas,"door",at+Vector2(-11,-12),Vector2(22,22))
	if open:
		effect(canvas,"arc",at+Vector2(0,2),tick,Vector2(38,38),0.8)

## AD-015: placeholder element glyphs left of damage numbers (final art: AD-VFX-036).
static func damage_symbol(canvas: CanvasItem, symbol: String, center: Vector2, size: float = 10.0, shade: Color = Color.WHITE) -> void:
	var h := size / 2.0
	match symbol:
		"flame":
			canvas.draw_colored_polygon(PackedVector2Array([
				center+Vector2(-h,h),center+Vector2(-h,-h*0.2),center+Vector2(-h*0.5,-h*0.7),
				center+Vector2(-h*0.25,-h*0.1),center+Vector2(0,-h),center+Vector2(h*0.25,-h*0.1),
				center+Vector2(h*0.5,-h*0.7),center+Vector2(h,-h*0.2),center+Vector2(h,h)]),shade)
		"droplet":
			canvas.draw_circle(center+Vector2(0,h*0.4),h*0.65,shade)
			canvas.draw_colored_polygon(PackedVector2Array([
				center+Vector2(0,-h),center+Vector2(h*0.6,h*0.25),center+Vector2(-h*0.6,h*0.25)]),shade)
		"bolt":
			canvas.draw_colored_polygon(PackedVector2Array([
				center+Vector2(h*0.3,-h),center+Vector2(-h*0.6,h*0.1),center+Vector2(-h*0.05,h*0.1),
				center+Vector2(-h*0.3,h),center+Vector2(h*0.6,-h*0.2),center+Vector2(h*0.05,-h*0.2)]),shade)
