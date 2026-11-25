extends RefCounted
## AD-239: elite enemy affixes (volatile, warded, hasted, splitting, shielded, anchored): data, spawn chance, bosses excluded, meta discovery, readability.
const Session = preload("res://combat/combat_session.gd")
const Flow = preload("res://world/run_flow.gd")
const Meta = preload("res://world/meta_progress.gd")
const SCREEN := "res://ui/compendium_screen.gd"
const DATA := "res://world/data/affixes_v1.json"
const AFFIX_SCRIPT := "res://world/affixes.gd"
const IDS := ["volatile","warded","hasted","splitting","shielded","anchored"]
const PLAYER := Vector2(150,450)
const FOE := Vector2(700,450)

func run(t) -> void:
	test_ad_239_a_volatile(t)
	test_ad_239_a_warded(t)
	test_ad_239_a_hasted(t)
	test_ad_239_a_splitting(t)
	test_ad_239_a_shielded(t)
	test_ad_239_a_anchored(t)
	test_ad_239_b_spawn_chance_by_depth(t)
	test_ad_239_c_never_on_bosses(t)
	test_ad_239_d_affix_discovered_in_meta(t)
	test_ad_239_e_readability_data(t)

func _data() -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(DATA))
	return parsed if parsed is Dictionary else {}

## Runtime load so this file parses before world/affixes.gd exists.
func _affixes():
	return load(AFFIX_SCRIPT) if ResourceLoader.exists(AFFIX_SCRIPT) else null

func _def(id: String) -> Dictionary:
	var defs = _data().get("affixes",{})
	var d = defs.get(id,{}) if defs is Dictionary else {}
	return d if d is Dictionary else {}

func _session(seed_value: int = 239):
	var s = Session.new(seed_value,"empty",0)
	s.defer_clear = true
	s.sim.actor.position = PLAYER
	return s

## Spawns `kind` (optionally with an affix) and returns the enemy, or null when the API is missing.
func _foe(t, s, kind: String, affix: String, at: Vector2 = FOE):
	var enemy = s.spawn_enemy(kind,at)
	var A = _affixes()
	if enemy != null and affix != "" and A != null:
		A.apply(s,enemy,affix)
	return enemy

func _travel(t, affix: String, kind: String = "bone_thrall") -> float:
	var s = _session()
	var enemy = _foe(t,s,kind,affix)
	if enemy == null:
		return -1.0
	var start: Vector2 = enemy.target.position
	for i in 20:
		s.sim.actor.position = PLAYER
		s.step()
	return start.distance_to(enemy.target.position)

func _kill(s, enemy) -> void:
	enemy.target.health.current = 0.0
	for i in 3:
		s.step()

func test_ad_239_a_volatile(t) -> void:
	var A = _affixes()
	t.check(A != null,"AD-239 volatile: Affixes script exists")
	if A == null:
		return
	var d := _def("volatile")
	t.check(not d.is_empty(),"AD-239 volatile: defined in data")
	var s = _session()
	var enemy = _foe(t,s,"bone_thrall","volatile",PLAYER+Vector2(60,0))
	t.check(enemy != null and enemy.affix == "volatile","AD-239 volatile: affix set on the enemy")
	if enemy == null:
		return
	var before: float = s.sim.actor.health.current
	var hazards_before: int = s.hazards.size()
	var events_before: int = s.pending_spawns.size()
	_kill(s,enemy)
	var telegraphs := 0
	for h in s.hazards:
		if h.get("position",Vector2.ZERO).distance_to(enemy.target.position) < 4.0:
			telegraphs += 1
	t.check(telegraphs > 0 or s.hazards.size() > hazards_before,"AD-239 volatile: death creates a blast hazard at the elite's position")
	t.equal(s.sim.actor.health.current,before,"AD-239 volatile: blast does not damage instantly")
	var ticks := int(d.get("telegraph_ticks",0))
	t.check(ticks > 0,"AD-239 volatile: telegraph ticks are data")
	for i in ticks+30:
		s.sim.actor.position = PLAYER+Vector2(60,0)
		s.step()
	t.check(s.sim.actor.health.current < before,"AD-239 volatile: blast damages the player after its telegraph")

func test_ad_239_a_warded(t) -> void:
	var A = _affixes()
	t.check(A != null,"AD-239 warded: Affixes script exists")
	if A == null:
		return
	var d := _def("warded")
	var weak := float(d.get("weak_multiplier",0.0))
	t.check(weak > 1.0,"AD-239 warded: weak multiplier from data is above 1")
	var s = _session()
	var enemy = _foe(t,s,"bone_thrall","warded")
	t.check(enemy != null and enemy.affix == "warded","AD-239 warded: affix set")
	if enemy == null:
		return
	var immune := ""
	var counter := ""
	for channel in ["fire","water","lightning","earth","wind","ice","physical","force"]:
		var r := float(enemy.target.health.resistances.get(channel,0.0))
		if r >= 1.0:
			immune = channel
		elif r < 0.0:
			counter = channel
	t.check(immune != "" and counter != "","AD-239 warded: one immune channel and one weak counter channel")
	if immune == "" or counter == "":
		return
	var base := float(s.data["enemies"]["bone_thrall"]["hp"])
	var plain = _foe(t,s,"bone_thrall","",FOE+Vector2(0,120))
	var plain_dealt: float = plain.target.receive_damage(10.0,counter,0,1.0)
	var immune_dealt: float = enemy.target.receive_damage(10.0,immune,0,1.0)
	var weak_dealt: float = enemy.target.receive_damage(10.0,counter,0,1.0)
	t.equal(immune_dealt,0.0,"AD-239 warded: immune essence deals 0")
	t.check(weak_dealt > plain_dealt*1.0 and absf(weak_dealt/plain_dealt-weak) < 0.05,"AD-239 warded: counter essence takes the data weak multiplier")
	t.check(base > 0.0,"AD-239 warded: baseline hp known")

func test_ad_239_a_hasted(t) -> void:
	var A = _affixes()
	t.check(A != null,"AD-239 hasted: Affixes script exists")
	if A == null:
		return
	var mult := float(_def("hasted").get("speed_multiplier",0.0))
	t.check(absf(mult-1.30) < 0.001,"AD-239 hasted: data speed multiplier is 1.30")
	var base := _travel(t,"")
	var fast := _travel(t,"hasted")
	t.check(base > 0.0 and fast > 0.0,"AD-239 hasted: enemies move")
	if base > 0.0:
		t.check(absf(fast/base-mult) < 0.03,"AD-239 hasted: travels 1.30x the unaffixed distance")

func test_ad_239_a_splitting(t) -> void:
	var A = _affixes()
	t.check(A != null,"AD-239 splitting: Affixes script exists")
	if A == null:
		return
	var s = _session()
	var parent = _foe(t,s,"bone_thrall","splitting")
	t.check(parent != null and parent.affix == "splitting","AD-239 splitting: affix set")
	if parent == null:
		return
	var before: int = s.enemies.size()
	var parent_hp: float = parent.target.health.maximum
	var parent_radius: float = parent.target.radius
	_kill(s,parent)
	var children: Array = s.enemies.slice(before)
	t.equal(children.size(),2,"AD-239 splitting: two children spawn on death")
	for child in children:
		t.check(child.target.health.maximum < parent_hp and child.target.radius < parent_radius,"AD-239 splitting: children have lower hp and radius")
		t.equal(child.affix,"","AD-239 splitting: children carry no affix")
	for i in 60:
		s.step()
	t.equal(s.enemies.size(),before+2,"AD-239 splitting: no recursive splitting")

func test_ad_239_a_shielded(t) -> void:
	var A = _affixes()
	t.check(A != null,"AD-239 shielded: Affixes script exists")
	if A == null:
		return
	var s = _session()
	var enemy = _foe(t,s,"bone_thrall","shielded")
	t.check(enemy != null and enemy.affix == "shielded","AD-239 shielded: affix set")
	if enemy == null:
		return
	enemy.heading = Vector2.LEFT
	s.sim.actor.position = FOE+Vector2(-200,0)
	s.step()
	var front: float = enemy.target.damage_scale
	enemy.heading = Vector2.RIGHT
	s.step()
	var back: float = enemy.target.damage_scale
	t.check(front < 1.0 and front >= 0.0,"AD-239 shielded: frontal projectile damage is scaled down")
	t.check(front < float(_def("shielded").get("front_damage_scale",1.0))+0.001,"AD-239 shielded: scale comes from data")
	t.equal(back,1.0,"AD-239 shielded: hit from behind is full damage")

func test_ad_239_a_anchored(t) -> void:
	var A = _affixes()
	t.check(A != null,"AD-239 anchored: Affixes script exists")
	if A == null:
		return
	var mult := float(_def("anchored").get("speed_multiplier",0.0))
	t.check(absf(mult-0.85) < 0.001,"AD-239 anchored: data speed multiplier is 0.85")
	var base := _travel(t,"")
	var slow := _travel(t,"anchored")
	if base > 0.0:
		t.check(absf(slow/base-mult) < 0.03,"AD-239 anchored: travels 0.85x the unaffixed distance")
	var s = _session()
	var enemy = _foe(t,s,"rune_sentry","anchored")
	var twin = _foe(t,s,"rune_sentry","",FOE+Vector2(0,150))
	if enemy == null or twin == null:
		t.check(false,"AD-239 anchored: stationary enemies spawn")
		return
	enemy.target.impulse = Vector2(600,0)
	twin.target.impulse = Vector2(600,0)
	s.step()
	t.check(enemy.target.impulse.is_zero_approx(),"AD-239 anchored: knockback impulse is ignored")
	t.check(not twin.target.impulse.is_zero_approx(),"AD-239 anchored: control enemy still takes knockback")

func test_ad_239_b_spawn_chance_by_depth(t) -> void:
	var A = _affixes()
	t.check(A != null,"AD-239 spawn: Affixes script exists")
	var data := _data()
	var table = data.get("spawn_chance_by_depth",{})
	t.equal(table,{"2":0.20,"3":0.35,"optional":0.50},"AD-239 spawn: chance table in data")
	t.equal(int(data.get("min_room",0)),2,"AD-239 spawn: min_room is 2 in data")
	t.equal(data.get("affixes",{}).keys().size() if data.get("affixes") is Dictionary else 0,6,"AD-239 spawn: six affixes defined")
	if A == null:
		return
	t.equal(A.chance_for(2,false),0.20,"AD-239 spawn: room 2 chance")
	t.equal(A.chance_for(3,false),0.35,"AD-239 spawn: room 3 chance")
	t.equal(A.chance_for(1,false),0.0,"AD-239 spawn: room 1 never")
	for room in [0,1,2,3,5]:
		t.equal(A.chance_for(room,true),0.50,"AD-239 spawn: optional room %d chance" % room)
	var hits := {2:0,3:0,-1:0}
	var early := 0
	var valid := true
	var seeds := 2000
	for i in seeds:
		if A.roll(i,1,false) != "":
			early += 1
		var r2: String = A.roll(i,2,false)
		var r3: String = A.roll(i,3,false)
		var ro: String = A.roll(i,4,true)
		valid = valid and r2 in [""]+IDS and r3 in [""]+IDS and ro in [""]+IDS
		hits[2] += int(r2 != "")
		hits[3] += int(r3 != "")
		hits[-1] += int(ro != "")
		if A.roll(i,2,false) != r2:
			valid = false
	t.equal(early,0,"AD-239 spawn: room 1 never rolls an affix")
	t.check(valid,"AD-239 spawn: roll returns '' or a known id (one affix max) and is deterministic")
	t.check(absf(float(hits[2])/seeds-0.20) <= 0.04,"AD-239 spawn: room 2 frequency near 20%")
	t.check(absf(float(hits[3])/seeds-0.35) <= 0.04,"AD-239 spawn: room 3 frequency near 35%")
	t.check(absf(float(hits[-1])/seeds-0.50) <= 0.04,"AD-239 spawn: optional frequency near 50%")
	var seen := {}
	for i in seeds:
		seen[A.roll(i,4,true)] = true
	for id in IDS:
		t.check(seen.has(id),"AD-239 spawn: %s can be rolled" % id)

func test_ad_239_c_never_on_bosses(t) -> void:
	var A = _affixes()
	t.check(A != null,"AD-239 bosses: Affixes script exists")
	var s = _session()
	var mini = s.spawn_mini_boss("ruins_adept_elite",Vector2(700,300))
	var boss = s.spawn_boss({"kind":"test_warden","hp":300,"radius":30,"recovery_ticks":10,"min_telegraph_ticks":36,"shot_speed":300,
		"shot_spread":0,"shot_damage":10,"radial_shots":4,"radial_damage":6,"fan_shots":3,"fan_arc_degrees":40,"telegraph_radius":190,
		"anchors":[[400,200],[1000,200],[700,750]],"phases":[{"threshold":1.0,"windup_ticks":40,"patterns":["fan"]}]},Vector2(900,500))
	t.check(mini != null and boss != null,"AD-239 bosses: mini-boss and boss spawn")
	for e in [mini,boss]:
		if e != null:
			t.equal(str(e.get("affix")),"","AD-239 bosses: spawn leaves no affix")
	if A == null:
		return
	for e in [mini,boss]:
		if e != null:
			A.apply(s,e,"hasted")
			t.equal(str(e.get("affix")),"","AD-239 bosses: apply is a no-op on boss/mini-boss")
	var hp_boss: float = boss.target.health.maximum
	A.apply(s,boss,"warded")
	t.equal(boss.target.health.maximum,hp_boss,"AD-239 bosses: apply changes nothing on a boss")
	t.check(boss.target.health.resistances == {} or not boss.target.health.resistances.values().has(1.0),"AD-239 bosses: boss gains no immunity")
	for tag in ["boss","mini_boss"]:
		var tagged = s.spawn_enemy("bone_thrall",Vector2(500,650))
		tagged.target.tags.append(tag)
		A.apply(s,tagged,"hasted")
		t.equal(tagged.affix,"","AD-239 bosses: %s-tagged enemy never receives an affix" % tag)

func test_ad_239_d_affix_discovered_in_meta(t) -> void:
	var A = _affixes()
	t.check("affixes" in Meta.categories(),"AD-239 meta: categories include affixes")
	var empty := Meta.empty_meta()
	t.check(empty["discovered"].has("affixes"),"AD-239 meta: empty meta has an affixes list")
	var added := Meta.merge(empty,{"affixes":["hasted","volatile"]})
	t.equal(added.get("affixes"),["hasted","volatile"],"AD-239 meta: merge reports the new affixes")
	t.equal(empty["discovered"].get("affixes"),["hasted","volatile"],"AD-239 meta: stored under meta affixes")
	t.equal(Meta.counts(empty).get("affixes"),2,"AD-239 meta: counts include affixes")
	t.check(Meta.valid_meta(empty),"AD-239 meta: valid_meta accepts affixes")
	var cats: Dictionary = load(SCREEN).catalogs_by_category()
	var listed: Array = cats.get("affixes",[])
	var sorted_ids := IDS.duplicate()
	sorted_ids.sort()
	t.equal(listed,sorted_ids,"AD-239 meta: compendium catalogs the six affix ids")
	if A == null:
		t.check(false,"AD-239 meta: Affixes script exists")
		return
	var flow = Flow.new(4242,Flow.CONFIG_V2)
	for i in 5:
		flow.step({})
	t.check(flow.discoveries().has("affixes"),"AD-239 meta: discoveries has an affixes list")
	t.equal(flow.discoveries().get("affixes"),[],"AD-239 meta: nothing discovered before an affixed elite appears")
	var host = null
	for e in flow.session.enemies:
		if e.get("affix") != null and not ("boss" in e.target.tags):
			host = e
			break
	if host == null:
		host = flow.session.spawn_enemy("bone_thrall",flow.session.sim.actor.position+Vector2(120,0))
	if host != null:
		A.apply(flow.session,host,"hasted")
		flow.step({})
		t.equal(flow.discoveries().get("affixes"),["hasted"],"AD-239 meta: a seen affixed elite is discovered")
	else:
		t.check(false,"AD-239 meta: could not place an enemy in the flow session")

func test_ad_239_e_readability_data(t) -> void:
	var defs = _data().get("affixes",{})
	t.check(defs is Dictionary and defs.keys().size() == 6,"AD-239 readability: six affixes in data")
	if not (defs is Dictionary):
		return
	var keys := {}
	var csv := FileAccess.open("res://i18n/strings_en.csv",FileAccess.READ)
	csv.get_csv_line()
	while not csv.eof_reached():
		var row := csv.get_csv_line()
		if row.size() >= 2:
			keys[row[0]] = true
	t.check(keys.has("compendium.section.enemies"),"AD-239 readability: i18n table readable")
	var colors := {}
	for id in IDS:
		var d := _def(id)
		var hex := str(d.get("outline_color",""))
		t.check(Color.html(hex).a > 0.0 and hex.begins_with("#") and hex.length() in [7,9],"AD-239 readability: %s outline_color is hex" % id)
		colors[hex.to_lower()] = true
		t.check(str(d.get("icon","")) != "","AD-239 readability: %s has an icon cell id" % id)
		var name_key := str(d.get("name_key",""))
		t.check(name_key != "" and keys.has(name_key),"AD-239 readability: %s name key is in the i18n table" % id)
	t.equal(colors.size(),6,"AD-239 readability: outline colours are distinct")
	var A = _affixes()
	if A != null:
		t.check(A.definitions().keys().size() == 6,"AD-239 readability: Affixes.definitions lists six")
		for id in IDS:
			t.equal(A.outline_color(id),Color.html(str(_def(id).get("outline_color",""))),"AD-239 readability: %s outline_color matches data" % id)
