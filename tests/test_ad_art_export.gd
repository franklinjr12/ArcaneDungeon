extends RefCounted
const ART = preload("res://ui/pixel_art_renderer.gd")
## AD-030: every art/export manifest entry loads as SpriteFrames and matches its Aseprite json.
const MANIFEST := "res://art/export/manifest.json"

func run(t) -> void:
	var m = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	t.check(m is Dictionary, "AD-030 manifest parses")
	if not m is Dictionary:
		return
	var assets: Dictionary = m["assets"]
	t.check(assets.size() >= 30, "AD-030 manifest has >= 30 assets")
	var sprites := 0
	for stem in assets:
		var e: Dictionary = assets[stem]
		var j = JSON.parse_string(FileAccess.get_file_as_string(e["json"]))
		t.check(j is Dictionary, "AD-030 json parses: " + stem)
		if e["png"] == null:
			t.equal(e.get("kind", ""), "swap_table", "AD-030 swap table: " + stem)
			continue
		sprites += 1
		var tex = load(e["png"])
		t.check(tex is Texture2D, "AD-030 png loads: " + stem)
		if not tex is Texture2D or not j is Dictionary:
			continue
		if e.get("kind", "") in ["glyph_atlas", "icon_atlas"]:
			continue
		var tsize: Vector2i = Vector2i(tex.get_size())
		if e.get("glow") != null:
			var gt = load(e["glow"])
			t.check(gt is Texture2D, "AD-154 glow png loads: " + stem)
			var gj_path: String = str(e["glow"]).get_basename() + ".json"
			if gt is Texture2D and FileAccess.file_exists(gj_path):
				# AD-155: AD-119/AD-110 glows are packed/padded separately; their own json is authoritative
				var gj = JSON.parse_string(FileAccess.get_file_as_string(gj_path))
				t.check(gj is Dictionary and gj.has("frames"), "AD-155 glow json parses: " + stem)
				if gj is Dictionary and gj.has("frames"):
					for gf in gj["frames"]:
						var gr: Dictionary = gf["frame"]
						t.check(gr["x"] >= 0 and gr["y"] >= 0 and gr["x"] + gr["w"] <= gt.get_width() and gr["y"] + gr["h"] <= gt.get_height(), "AD-155 glow rect inside glow texture: %s/%s" % [stem, gf["filename"]])
			elif gt is Texture2D:
				t.equal(Vector2i(gt.get_size()), tsize, "AD-154 glow size matches base: " + stem)
		var frames: Array = j["frames"]
		var tags: Array = j["meta"]["frameTags"]
		var sf: SpriteFrames = ART.build_sprite_frames(stem)
		var names := []
		for tg in tags:
			names.append(str(tg["name"]))
		var got := Array(sf.get_animation_names())
		got.sort()
		names.sort()
		t.equal(got, names, "AD-030 animation names match json: " + stem)
		var mtags: Array = e["tags"].keys()
		mtags.sort()
		t.equal(mtags, names, "AD-030 manifest tags match json: " + stem)
		for tg in tags:
			var n := str(tg["name"])
			var cnt: int = int(tg["to"]) - int(tg["from"]) + 1
			t.equal(sf.get_frame_count(n), cnt, "AD-030 frame count %s/%s" % [stem, n])
			t.equal(int(e["tags"][n]["frames"]), cnt, "AD-030 manifest frames %s/%s" % [stem, n])
			for i in cnt:
				var ms: int = int(frames[int(tg["from"]) + i]["duration"])
				t.equal(int(e["tags"][n]["ms"][i]), ms, "AD-030 manifest ms %s/%s/%d" % [stem, n, i])
				var got_ms: float = sf.get_frame_duration(n, i) / sf.get_animation_speed(n) * 1000.0
				t.check(absf(got_ms - ms) < 0.01, "AD-030 SpriteFrames ms %s/%s/%d" % [stem, n, i])
		for f in frames:
			var r: Dictionary = f["frame"]
			t.check(r["x"] >= 0 and r["y"] >= 0 and r["x"] + r["w"] <= tsize.x and r["y"] + r["h"] <= tsize.y, "AD-030 region inside texture: %s/%s" % [stem, f["filename"]])
		var pivot = null
		for s in j["meta"].get("slices", []):
			if s["name"] == "pivot":
				var b: Dictionary = s["keys"][0]["bounds"]
				pivot = [b["x"], b["y"]]
		if e["category"] in ["vfx", "ico"] and pivot == null:
			t.check(e["pivot"] is Array and e["pivot"].size() == 2, "AD-039 manifest pivot (canvas centre): " + stem)
			continue
		t.check(pivot != null, "AD-030 pivot slice in json: " + stem)
		t.check(e["slices"].has("pivot"), "AD-030 pivot slice in manifest: " + stem)
		if pivot != null:
			t.equal(e["pivot"], pivot, "AD-030 manifest pivot: " + stem)
	t.check(sprites >= 30, "AD-030 sprite entries >= 30")
	_cistern(t, m, assets)
	_demo_x2(t, m, assets)
	_demo_fx(t)
	_engine_map(t, assets)
	_actors(t)
	_renderer(t)
	_env_props(t)

## AD-154: Cistern tileset, arena, AD-120 props and AD-122 chest/altar are in the manifest.
func _cistern(t, m: Dictionary, assets: Dictionary) -> void:
	for row in ["AD-099", "AD-100", "AD-120", "AD-122"]:
		t.check(row in m["source_rows"], "AD-154 source row " + row)
		var n := 0
		for stem in assets:
			if assets[stem]["row"] == row:
				n += 1
		t.check(n > 0, "AD-154 assets from " + row)
	t.check(assets.has("ad_til_flooded_cistern"), "AD-154 flooded cistern tiles")
	if assets.has("ad_til_flooded_cistern"):
		var tg: Array = assets["ad_til_flooded_cistern"]["tags"].keys()
		tg.sort()
		for n in ["floor", "shore", "deep", "water_loop", "deep_loop"]:
			t.check(n in tg, "AD-154 flooded cistern tag " + n)
	t.equal(assets.get("ad_fx_cistern_motes", {}).get("category", ""), "vfx", "AD-154 motes are vfx")
	t.equal(assets.get("ad_fx_cistern_motes", {}).get("id", ""), "AD-TIL-010-motes", "AD-154 motes id")
	for s in ["brazier_cistern", "brazier_ruins", "breakable_urn", "breakable_urn_cistern", "burnable_crate_cistern", "burnable_crate_ruins", "cobweb_cistern", "cobweb_ruins", "cracked_wall_cistern", "cracked_wall_ruins", "ice_patch", "puddle_cistern", "puddle_ruins"]:
		t.check(assets.has("ad_prp_" + s) and assets["ad_prp_" + s]["row"] == "AD-120", "AD-154 AD-120 prop " + s)
	for s in ["treasure_chest", "challenge_altar"]:
		for v in ["ruins", "cistern"]:
			var k := "ad_prp_%s_%s" % [s, v]
			t.check(assets.has(k) and assets[k]["row"] == "AD-122", "AD-154 AD-122 " + k)
	for lv in ["high", "mid", "low"]:
		for suf in ["", "_glow"]:
			t.check(FileAccess.file_exists("res://art/export/til/ad_til_archivist_arena_lvl_%s%s.png" % [lv, suf]), "AD-154 arena level %s%s" % [lv, suf])

const BEAM_ELEMENTS := ["fire", "water", "lightning", "ice", "force", "neutral"]
const DEMO_ICONS := ["ad_ico_cold", "ad_ico_force", "ad_ico_beam", "ad_ico_field", "ad_ico_chain", "ad_ico_expand", "ad_ico_rapid", "ad_ico_on_kill", "ad_ico_on_expire", "ad_ico_timer", "ad_ico_chilled", "ad_ico_frozen", "ad_ico_brittle", "ad_ico_hp_up", "ad_ico_mana_up", "ad_ico_dash_up", "ad_ico_reroll", "ad_ico_undiscovered"]
const AD114_STEMS := ["ad_vfx_mod_chain", "ad_vfx_mod_rapid", "ad_vfx_trig_on_kill_glyph", "ad_vfx_trig_on_expire_glyph", "ad_vfx_trig_timer_glyph", "ad_vfx_status_chilled", "ad_vfx_status_frozen", "ad_vfx_status_brittle", "ad_vfx_shatter", "ad_vfx_reaction_steam", "ad_vfx_reaction_flash_freeze"]
const COOKIES := ["boss_key", "brazier", "grate_shaft", "radial_soft", "rune_circle", "spell_cold", "spell_fire", "spell_force", "spell_lightning", "spell_nature", "spell_water", "torch_flicker", "window_shaft"]
const PARTICLES := ["droplet", "dust", "ember", "frost", "glyph", "mote", "smoke", "spark", "wisp"]

func _json(path: String):
	return JSON.parse_string(FileAccess.get_file_as_string(path))

## AD-155: rune/status/artifact icons, Cold/Force/Beam/Field VFX (AD-119 glow cleanup), AD-114 VFX, AD-117 cookies/particles.
func _demo_x2(t, m: Dictionary, assets: Dictionary) -> void:
	for row in ["AD-110", "AD-111", "AD-112", "AD-113", "AD-114", "AD-115", "AD-116", "AD-117", "AD-119", "AD-123"]:
		t.check(row in m["source_rows"], "AD-155 source row " + row)
	# AD-111/112/113 stems are all re-exported by AD-119 (row AD-119 wins), so only AD-114/117 own assets
	for row in ["AD-114", "AD-117", "AD-119"]:
		var n := 0
		for stem in assets:
			if assets[stem]["row"] == row:
				n += 1
		t.check(n > 0, "AD-155 assets from " + row)
	var glow_stems := []
	for el in ["ice", "force"]:
		for kind in ["projectile", "impact", "burst", "orb"]:
			glow_stems.append("ad_vfx_%s_%s" % [el, kind])
	for el in BEAM_ELEMENTS:
		for part in ["start", "segment", "end"]:
			glow_stems.append("ad_vfx_beam_%s_%s" % [el, part])
	for el in ["fire", "water", "lightning", "ice", "force"]:
		glow_stems.append("ad_vfx_%s_field" % el)
	t.equal(glow_stems.size(), 31, "AD-155 AD-119 stem count")
	for stem in glow_stems:
		var e: Dictionary = assets.get(stem, {})
		t.equal(e.get("row", ""), "AD-119", "AD-155 AD-119 row: " + stem)
		t.equal(e.get("category", ""), "vfx", "AD-155 vfx: " + stem)
		t.check(e.get("glow") != null and load(e["glow"]) is Texture2D, "AD-155 glow png: " + stem)
	for stem in AD114_STEMS:
		t.equal(assets.get(stem, {}).get("row", ""), "AD-114", "AD-155 AD-114 stem " + stem)
	var atlas: Dictionary = assets.get("ad_ico_atlas_demo", {})
	t.equal(atlas.get("row", ""), "AD-123", "AD-155 demo atlas is the AD-123 extension")
	var idx = _json("res://art/export/ico/ad_ico_atlas_demo_index.json")
	t.check(idx is Dictionary and idx.has("icons"), "AD-155 demo atlas index parses")
	if idx is Dictionary and idx.has("icons"):
		for icon in DEMO_ICONS:
			t.check(idx["icons"].has(icon), "AD-155 demo atlas icon " + icon)
	for stem in ["ad_ico_status8_demo", "ad_ico_merchant8"]:
		t.check(assets.has(stem) and load(assets[stem]["png"]) is Texture2D and load(assets[stem]["glow"]) is Texture2D, "AD-155 8 px icons: " + stem)
	var art: Dictionary = assets.get("ad_ico_artifacts", {})
	t.equal(art.get("kind", ""), "icon_atlas", "AD-155 artifact atlas kind")
	t.equal(art.get("row", ""), "AD-115", "AD-155 artifact atlas row")
	for key in ["png", "glow", "png_32", "glow_32"]:
		t.check(art.has(key) and load(art[key]) is Texture2D, "AD-155 artifact atlas " + key)
	var aidx = _json(str(art.get("json", "")))
	var defs = _json("res://world/data/artifacts_v1.json")
	if aidx is Dictionary and defs is Dictionary:
		for id in defs["artifacts"]:
			t.check(aidx["artifacts"].has(id), "AD-155 artifact icon " + id)
		t.equal(aidx["artifacts"].size(), defs["artifacts"].size(), "AD-155 artifact icon count")
	else:
		t.check(false, "AD-155 artifact index parses")
	for c in COOKIES:
		var k: String = "ad_fx_cookie_" + c
		t.check(assets.has(k) and assets[k]["category"] == "vfx" and assets[k]["row"] == "AD-117", "AD-155 cookie " + k)
	for p in PARTICLES:
		for sz in [8, 16]:
			var k: String = "ad_fx_ptc_%s_%d" % [p, sz]
			t.check(assets.has(k) and assets[k]["category"] == "vfx" and assets[k]["row"] == "AD-117", "AD-155 particle " + k)
			t.check(assets.get(k, {}).get("mask") != null, "AD-155 particle mask " + k)

const DEMO_FX := ["projectile.cold", "impact.cold", "burst.cold", "orb.cold", "projectile.force", "impact.force", "burst.force",
	"orb.force", "status.chilled", "status.frozen", "status.brittle", "reaction.shatter", "reaction.steam", "reaction.flash_freeze",
	"mod.chain", "mod.rapid", "trigger.on_kill", "trigger.on_expire", "trigger.timer"]
const OLD_RUNE_ICONS := {"essence.cold": "ad_ico_water", "essence.force": "ad_ico_projectile", "form.beam": "ad_ico_projectile",
	"form.field": "ad_ico_burst", "mod.chain": "ad_ico_split", "mod.expand": "ad_ico_burst", "mod.rapid": "ad_ico_homing",
	"trigger.on_kill": "ad_ico_on_hit", "trigger.on_expire": "ad_ico_on_hit", "trigger.timer": "ad_ico_on_hit"}

## AD-155 step 2: Cold/Force + AD-114 FX events resolve, rune icons are real demo-atlas keys, no FX falls back.
func _demo_fx(t) -> void:
	ART.fx_fallbacks.clear()
	for ev in DEMO_FX:
		t.check(ART.FX_EVENTS.has(ev), "AD-155 FX_EVENTS has " + ev)
		var fr: Dictionary = ART.fx_frame(ev, 0)
		t.check(not fr.is_empty(), "AD-155 fx_frame not empty: " + ev)
		if fr.is_empty():
			continue
		var tex: Texture2D = load(ART.export_manifest()[fr["stem"]]["png"])
		var r: Rect2 = fr["region"]
		t.check(r.size.x > 0 and r.position.x >= 0 and r.position.y >= 0 and r.end.x <= tex.get_width() and r.end.y <= tex.get_height(), "AD-155 fx region inside texture: " + ev)
		var gl: Dictionary = ART.fx_glow_frame(fr)
		t.check(not gl.is_empty() and Rect2(Vector2.ZERO, gl["tex"].get_size()).encloses(gl["region"]), "AD-155 fx glow region inside texture: " + ev)
	for ev in ART.FX_EVENTS:
		ART.fx_frame(ev, 0)
		t.check(not ART.fx_frame(ev, 0).is_empty(), "AD-155 FX_EVENTS entry mapped: " + ev)
	t.check(ART.fx_fallbacks.is_empty(), "AD-155 fx_fallbacks stays empty")
	for ev in ART.FX_UNEMITTED:
		t.check(ART.FX_EVENTS.has(ev), "AD-155 unemitted event is a known event: " + ev)
	var map: Dictionary = ART.export_map()
	t.equal(map["icons"], "ad_ico_atlas_demo", "AD-155 icons atlas is the demo atlas")
	var idx = _json("res://art/export/ico/ad_ico_atlas_demo_index.json")
	var runes = _json("res://magic/data/runes_v2.json")
	var ids: Array = map["rune_icons"].keys()
	if runes is Dictionary:
		for r in runes["runes"]:
			t.check(map["rune_icons"].has(r["id"]), "AD-155 rune mapped: " + str(r["id"]))
	for id in ids:
		t.check(idx["icons"].has(map["rune_icons"][id]), "AD-155 rune icon in demo atlas: " + id)
	for id in OLD_RUNE_ICONS:
		t.check(map["rune_icons"][id] != OLD_RUNE_ICONS[id], "AD-155 no placeholder icon for " + id)
	for k in ["hp_up", "mana_up", "dash_up", "reroll", "undiscovered"]:
		t.check(map["ui_icons"].has(k) and idx["icons"].has(map["ui_icons"][k]), "AD-155 ui icon " + k)

func _engine_map(t, assets: Dictionary) -> void:
	t.check(not ART.use_art_export, "AD-030 art export off by default")
	t.check(ART.toggle_art_export(), "AD-030 toggle on")
	t.check(not ART.toggle_art_export(), "AD-030 toggle off")
	var map: Dictionary = ART.export_map()
	for kind in map["entities"]:
		var stem: String = map["entities"][kind]
		t.check(assets.has(stem), "AD-030 map entity in manifest: " + kind)
		for st in ["idle", "move", "cast", "hit", "dead"]:
			t.check(assets[stem]["tags"].has(map["states"][stem][st]), "AD-030 map tag %s/%s" % [stem, st])
	t.check(assets[map["floor"]["asset"]]["tags"].has(map["floor"]["tag"]), "AD-030 floor tag exists")
	t.equal(ART.build_sprite_frames("ad_chr_mage").get_animation_names().size(), 18, "AD-030 mage has 18 animations")
	var f0: Dictionary = ART.export_frame_for("mage", "idle", 0)
	t.equal(f0["index"], 0, "AD-030 tick 0 -> frame 0")
	t.equal(ART.export_frame_for("mage", "idle", int(ceil(f0["total_ms"] * 60.0 / 1000.0)))["index"], 0, "AD-030 idle loops")
	var dead: Dictionary = ART.export_frame_for("bone_thrall", "dead", 100000)
	t.equal(dead["index"], 4, "AD-030 dead holds last frame")
	# Drawing is only legal inside _draw(); the headless runner has no render pass,
	# so the draw path is covered by frame/atlas lookups above instead.
	ART.use_art_export = true
	t.check(ART.export_frame_for("undead_warden", "cast", 5).has("region"), "AD-030 export frame has atlas region")
	ART.use_art_export = false

const ACTORS_MANIFEST := "res://art/export/actors/actors_manifest.json"
const TUNING := "res://combat/combat_tuning_v1.json"
const ENEMY_TAGS := ["idle_side", "move_side", "telegraph_side", "attack_side", "hit_side", "death_side"]

## AD-154: actors_manifest.json matches each sheet json (tags, ms, pivot, hurtbox, glow rects); enemies carry the canvas tags.
func _actors(t) -> void:
	var m = JSON.parse_string(FileAccess.get_file_as_string(ACTORS_MANIFEST))
	t.check(m is Dictionary and m.has("actors"), "AD-154 actors manifest parses")
	if not m is Dictionary:
		return
	var actors: Dictionary = m["actors"]
	var jsons := {}
	for kind in actors:
		var ent: Dictionary = actors[kind]
		for key in ent["sheets"]:
			var sh: Dictionary = ent["sheets"][key]
			var j = JSON.parse_string(FileAccess.get_file_as_string(sh["json"]))
			t.check(j is Dictionary, "AD-154 json parses: %s/%s" % [kind, key])
			t.check(load(sh["png"]) is Texture2D, "AD-154 png loads: %s/%s" % [kind, key])
			if not j is Dictionary:
				continue
			jsons[kind + "/" + key] = j
			var slices := {}
			for s in j["meta"].get("slices", []):
				slices[s["name"]] = s["keys"][0]["bounds"]
			t.check(slices.has("pivot") and slices.has("hurtbox"), "AD-154 pivot/hurtbox slices: %s/%s" % [kind, key])
			if slices.has("pivot"):
				t.equal(sh["pivot"], [slices["pivot"]["x"], slices["pivot"]["y"]], "AD-154 pivot: %s/%s" % [kind, key])
			t.check(sh["hurtbox"] is Dictionary, "AD-154 hurtbox: %s/%s" % [kind, key])
			if sh.get("glow_png") != null:
				var gtex = load(sh["glow_png"])
				t.check(gtex is Texture2D, "AD-154 glow png loads: %s/%s" % [kind, key])
				if gtex is Texture2D:
					for fi in sh["glow"]:
						var r: Dictionary = sh["glow"][fi]
						t.check(int(fi) < j["frames"].size() and r["x"] >= 0 and r["y"] >= 0 and r["x"] + r["w"] <= gtex.get_width() and r["y"] + r["h"] <= gtex.get_height(), "AD-154 glow rect inside texture: %s/%s/%s" % [kind, key, fi])
		for n in ent["tags"]:
			var tg: Dictionary = ent["tags"][n]
			var j = jsons.get(kind + "/" + str(tg["sheet"]))
			if j == null:
				continue
			var src := str(tg.get("src", n))
			var jt = null
			for x in j["meta"]["frameTags"]:
				if x["name"] == src:
					jt = x
			t.check(jt != null, "AD-154 json tag exists: %s/%s" % [kind, n])
			if jt == null:
				continue
			var f: int = int(tg["from"])
			var to: int = int(tg["to"])
			t.check(f >= int(jt["from"]) and f <= to and to <= int(jt["to"]), "AD-154 tag range inside source: %s/%s" % [kind, n])
			if not tg.has("src"):
				t.check(f == int(jt["from"]) and to == int(jt["to"]), "AD-154 tag from/to equals json: %s/%s" % [kind, n])
			t.equal(int(tg["frames"]), to - f + 1, "AD-154 tag frames: %s/%s" % [kind, n])
			var ms := []
			for i in range(f, to + 1):
				ms.append(int(j["frames"][i]["duration"]))
			var got := []
			for v in tg["ms"]:
				got.append(int(v))
			t.equal(got, ms, "AD-154 tag ms equals json: %s/%s" % [kind, n])
	var tuning = JSON.parse_string(FileAccess.get_file_as_string(TUNING))
	var kinds: Array = tuning["enemies"].keys() if tuning is Dictionary else []
	kinds.append("drowned_archivist")
	for kind in kinds:
		t.check(actors.has(kind), "AD-154 actor exists: " + kind)
		for n in ENEMY_TAGS:
			t.check(actors.has(kind) and actors[kind]["tags"].has(n), "AD-154 required tag %s/%s" % [kind, n])

const REAL_KINDS := ["ossuary_shieldbearer", "wailing_spirit", "corpse_bloat", "cistern_slime", "cistern_slimelet", "drowned_acolyte", "deep_eel", "lantern_wisp", "storm_crystal", "rust_golem", "drowned_archivist"]
const RUN_V2 := "res://world/data/run_v2.json"

func _windup_ok(t, kind: String, ticks: int, label: String) -> void:
	var tag := "telegraph_side" if ART.actor_has_tag(kind, "telegraph_side") else "telegraph_burst_side"
	var n := ART.actor_tag_frames(kind, tag)
	t.equal(ART.telegraph_anim_ticks(kind, ticks), ticks, "AD-154 telegraph covers windup: " + label)
	t.equal(ART.stretched_index(ticks - 1, ticks, n), n - 1, "AD-154 telegraph ends on last frame: " + label)

## AD-154: placeholders retired, telegraph stretch matches data windups, actor glow lookup/queue.
func _renderer(t) -> void:
	for k in REAL_KINDS:
		t.equal(ART.resolve_kind(k), k, "AD-154 resolve_kind own entry: " + k)
	t.check(ART.PLACEHOLDER_KIND.is_empty(), "AD-154 no placeholder kinds left")
	var spirit := ART.placeholder_modulate("wailing_spirit", Color.RED, true, false)
	t.check(is_equal_approx(spirit.a, 0.4), "AD-154 intangible alpha kept")
	t.check(spirit.r == 1.0 and spirit.g == 1.0 and spirit.b == 1.0, "AD-154 real art has no tint")
	t.check(is_equal_approx(ART.placeholder_modulate("deep_eel", Color.RED, false, true).a, 0.7), "AD-154 warning flicker alpha kept")
	var tuning = JSON.parse_string(FileAccess.get_file_as_string(TUNING))
	for kind in tuning["enemies"]:
		_windup_ok(t, kind, int(tuning["enemies"][kind]["telegraph_ticks"]), "enemy " + kind)
	for id in tuning["mini_bosses"]:
		var mb: Dictionary = tuning["mini_bosses"][id]
		_windup_ok(t, str(mb["kind"]), int(mb["windup_ticks"]), id + " windup")
		_windup_ok(t, str(mb["kind"]), int(mb["second_phase_windup_ticks"]), id + " phase 2")
	var run = JSON.parse_string(FileAccess.get_file_as_string(RUN_V2))
	for ph in run["bosses"]["cistern_boss"]["phases"]:
		_windup_ok(t, "drowned_archivist", int(ph["windup_ticks"]), "archivist %d" % int(ph["windup_ticks"]))
	for c in [["deep_eel", "telegraph_side"], ["mage", "channel_side"]]:
		var g := ART.actor_glow_frame(c[0], c[1], 0)
		t.check(not g.is_empty(), "AD-154 glow frame exists: " + c[0])
		if not g.is_empty():
			var r: Rect2 = g["region"]
			t.check(r.size.x > 0 and r.size.y > 0 and r.position.x >= 0 and r.position.y >= 0 and r.end.x <= g["tex"].get_width() and r.end.y <= g["tex"].get_height(), "AD-154 glow region inside texture: " + c[0])

## AD-154: env prop kinds map to imported AD-120 stems/tags for ruins and cistern.
func _env_props(t) -> void:
	var kinds: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://world/data/env_props_v1.json"))["kinds"]
	var man: Dictionary = ART.export_manifest()
	for kind in kinds:
		if kind == "ice":
			continue
		for stage in [0, 2]:
			var fr := ART.env_prop_frame(kind, "intact", true, stage, 0)
			var label := "%s stage %d" % [kind, stage]
			t.check(not fr.is_empty() and man.has(fr["stem"]) and man[fr["stem"]]["tags"].has(fr["tag"]), "AD-154 env prop maps: " + label)
	t.equal(ART.env_prop_frame("puddle", "frozen", false, 2, 0)["stem"], "ad_prp_ice_patch", "AD-154 frozen puddle is ice patch")
	t.equal(ART.env_prop_frame("urn", "intact", false, 0, 0)["stem"], "ad_prp_breakable_urn", "AD-154 ruins urn has no suffix")
	t.equal(ART.env_prop_frame("brazier", "intact", false, 2, 0)["tag"], "unlit", "AD-154 unlit brazier")
	t.equal(ART.env_prop_frame("crate", "burning", false, 0, 7)["tag"], "burning", "AD-154 burning crate")
	t.check(ART.env_prop_frame("crate", "destroyed", false, 0, 0).is_empty(), "AD-154 destroyed crate skipped")
