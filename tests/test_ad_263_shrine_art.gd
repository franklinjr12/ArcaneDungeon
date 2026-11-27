extends RefCounted
## AD-263: the AD-262 approved shrine sprites are imported unchanged and the AD-259 shrine.* art keys point at them.
## Pins: SHRINE_ART key map (data keys -> manifest stems), tags per object (interact in range, idol hit on damage),
## the 5x5 room mosaic layout. Drawing is not tested here (needs a display); see docs/ART_IMPLEMENTATION.md for captures.
const Art = preload("res://ui/pixel_art_renderer.gd")
const Flow = preload("res://world/run_flow.gd")

func run(t) -> void:
	test_ad_263_a_keys_point_at_imported_art(t)
	test_ad_263_b_tags_per_object(t)
	test_ad_263_c_state_selection(t)
	test_ad_263_d_room_mosaic_layout(t)

func _shrine_cfg() -> Dictionary:
	var shrine = JSON.parse_string(FileAccess.get_file_as_string(Flow.CONFIG_V2)).get("shrine",{})
	return shrine if shrine is Dictionary else {}

func test_ad_263_a_keys_point_at_imported_art(t) -> void:
	var shrine := _shrine_cfg()
	var manifest: Dictionary = Art.export_manifest()
	var keys: Array = [str(shrine.get("room_art_key",""))]
	for id in ["altar","statue","practice_idol"]:
		keys.append(str(shrine.get(id,{}).get("art_key","")))
	for key in keys:
		t.check(Art.SHRINE_ART.has(key),"AD-263a data key %s is in SHRINE_ART" % key)
		var stem: String = Art.SHRINE_ART.get(key,"")
		t.check(manifest.has(stem),"AD-263a %s points at manifest entry %s" % [key,stem])
		if manifest.has(stem):
			t.check(str(manifest[stem]["id"]).begins_with("AD-262-"),"AD-263a %s is an AD-262 import" % stem)
			t.check(str(manifest[stem]["category"]) in ["prp","npc","til"],"AD-263a %s is in prp, npc or til" % stem)
	var expected := {"shrine.room":"ad_til_shrine_mosaic","shrine.altar":"ad_prp_shrine_altar",
		"shrine.statue":"ad_npc_divine_statue","shrine.idol":"ad_npc_practice_idol"}
	for key in expected:
		t.equal(Art.SHRINE_ART.get(key,""),expected[key],"AD-263a key map %s" % key)

func test_ad_263_b_tags_per_object(t) -> void:
	var manifest: Dictionary = Art.export_manifest()
	var tags := {
		"ad_prp_shrine_altar": ["idle","interact"],
		"ad_npc_divine_statue": ["idle","interact","offering"],
		"ad_npc_practice_idol": ["idle","interact","hit"],
	}
	for stem in tags:
		for tag in tags[stem]:
			t.check(manifest.has(stem) and manifest[stem]["tags"].has(tag),"AD-263b %s has tag %s" % [stem,tag])
	if manifest.has("ad_til_shrine_mosaic"):
		var mosaic: Dictionary = manifest["ad_til_shrine_mosaic"]["tags"]
		t.equal(int(mosaic["centre"]["frames"]),9,"AD-263b mosaic centre is 3x3")
		t.equal(int(mosaic["edge"]["frames"]),4,"AD-263b mosaic has 4 edges")
		t.equal(int(mosaic["corner"]["frames"]),4,"AD-263b mosaic has 4 corners")

func test_ad_263_c_state_selection(t) -> void:
	var altar := Art.shrine_frame("shrine.altar","idle",0)
	t.equal(str(altar.get("tag","")),"idle","AD-263c altar idle when out of range")
	var lit := Art.shrine_frame("shrine.altar","interact",0)
	t.equal(str(lit.get("tag","")),"interact","AD-263c altar interact tag when in range")
	t.equal(str(Art.shrine_frame("shrine.altar","hit",0).get("tag","")),"idle","AD-263c altar has no hit tag, stays idle")
	var idol_hit := Art.shrine_frame("shrine.idol","hit",0,0)
	t.equal(str(idol_hit.get("tag","")),"hit","AD-263c idol hit tag on damage")
	t.equal(int(idol_hit.get("index",-1)),0,"AD-263c idol hit starts on its first frame")
	var idol_done := Art.shrine_frame("shrine.idol","hit",0,10000)
	t.equal(int(idol_done.get("index",-1)),2,"AD-263c idol hit holds its last frame once finished")
	var idol_idle := Art.shrine_frame("shrine.idol","idle",123)
	t.equal(str(idol_idle.get("tag","")),"idle","AD-263c idol returns to idle after the hit")
	t.check(Art.shrine_frame("shrine.unknown","idle",0).is_empty(),"AD-263c unknown key has no sprite (plinth fallback)")
	var region: Rect2 = lit.get("region",Rect2())
	t.check(region.size.x > 0 and region.size.y > 0,"AD-263c frame region is non-empty")

func test_ad_263_d_room_mosaic_layout(t) -> void:
	var seen := {}
	var kinds := {"corner":[],"edge":[],"centre":[]}
	for r in 5:
		for c in 5:
			var pick: Array = Art._mosaic_tile(r,c)
			seen["%s:%d" % [pick[0],pick[1]]] = true
			kinds[pick[0]].append(int(pick[1]))
	t.equal(kinds["corner"].size(),4,"AD-263d ring has 4 corners")
	t.equal(kinds["edge"].size(),12,"AD-263d ring has 12 edge cells")
	t.equal(kinds["centre"].size(),9,"AD-263d centre is 3x3")
	t.equal(seen.size(),17,"AD-263d every one of the 17 AD-262 tiles is used")
	t.equal(Art._mosaic_tile(0,0),["corner",0],"AD-263d NW corner is tile 0")
	t.equal(Art._mosaic_tile(0,4),["corner",1],"AD-263d NE corner is tile 1")
	t.equal(Art._mosaic_tile(4,4),["corner",2],"AD-263d SE corner is tile 2")
	t.equal(Art._mosaic_tile(4,0),["corner",3],"AD-263d SW corner is tile 3")
	t.equal(Art._mosaic_tile(2,2),["centre",4],"AD-263d centre of the medallion is centre tile 4")
