extends RefCounted
## AD-240: 12 new artifacts with combo tags. Step 1: data, tags, tag-biased rewards, card tag, meta unlocks.
const Artifacts = preload("res://world/artifacts.gd")
const Reward = preload("res://world/reward_generator.gd")
const Flow = preload("res://world/run_flow.gd")
const Meta = preload("res://world/meta_progress.gd")
const IDS := ["thunderhead","frostbrand","kindling","undertow","overcharge","shard_mail",
	"quicksilver_ink","conduit_coil","tidecaller_shell","mirror_glyph","grave_salt","fracture_lens"]
const TAGS := ["reaction","form","trigger","defence"]
const META_LOCKED := ["grave_salt","mirror_glyph","conduit_coil","thunderhead"]

func run(t) -> void:
	_data(t)
	_tag_bias(t)
	_card_tag(t)
	_meta_unlocks(t)

func _csv_keys() -> Dictionary:
	var keys := {}
	var csv := FileAccess.open("res://i18n/strings_en.csv", FileAccess.READ)
	csv.get_csv_line()
	while not csv.eof_reached():
		var row := csv.get_csv_line()
		if row.size() >= 2:
			keys[row[0]] = true
	return keys

func _tuning() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(Flow.CONFIG_V2))

func _run(seed_value: int, held: Array):
	var State = load("res://world/run_state.gd")
	var cfg: Dictionary = _tuning()
	var state = State.new()
	var formulas := {}
	for id in cfg["initial_formulas"]:
		formulas[id] = {"id":id}
	state.initialize(seed_value,cfg,formulas)
	state.artifacts = held.duplicate()
	return state

func _data(t) -> void:
	var defs: Dictionary = Artifacts.definitions()
	var keys := _csv_keys()
	t.equal(defs.size(),24,"AD-240 config has 24 artifacts")
	for id in defs:
		var def: Dictionary = defs[id]
		t.check(str(def.get("tag","")) in TAGS,"AD-240 %s has a valid tag" % id)
		t.equal(Artifacts.tag_of(id),str(def.get("tag","")),"AD-240 tag_of reads data for "+id)
		t.check(keys.has(str(def.get("name_key",""))) and keys.has(str(def.get("desc_key",""))),"AD-240 %s name/desc keys exist" % id)
		t.check(not def.get("params",{}).is_empty(),"AD-240 %s tunables live in params" % id)
	for id in IDS:
		t.check(defs.has(id),"AD-240 new artifact present: "+id)
	t.equal(Artifacts.tag_of("nope"),"","AD-240 tag_of unknown is empty")
	for tag in TAGS:
		t.check(keys.has("run.reward.artifact_tag_"+tag),"AD-240 tag label key exists: "+tag)
	t.equal(float(Artifacts.config().get("tag_bias",0.0)),0.4,"AD-240 tag_bias comes from data")

func _offered(seed_value: int, held: Array) -> String:
	var run_state = _run(seed_value,held)
	var card: Dictionary = Reward.artifact_choice(run_state,seed_value * 7919 + 13,true)
	return str(card.get("id",""))

func _tag_bias(t) -> void:
	var held := ["shatterheart"]
	var tag := Artifacts.tag_of("shatterheart")
	var n := 600
	var biased := 0
	var baseline := 0
	var pool_share := 0.0
	var candidates: Array = Artifacts.definitions().keys().filter(func(id): return id not in held)
	pool_share = float(candidates.filter(func(id): return Artifacts.tag_of(id) == tag).size())/float(candidates.size())
	for i in n:
		if Artifacts.tag_of(_offered(i,held)) == tag:
			biased += 1
		if Artifacts.tag_of(_offered(i,[])) == tag:
			baseline += 1
	var bias := float(Artifacts.config()["tag_bias"])
	var expected := bias+(1.0-bias)*pool_share
	var share := float(biased)/float(n)
	t.check(share > pool_share+0.15,"AD-240 held tag share %.2f clearly above pool share %.2f" % [share,pool_share])
	t.check(absf(share-expected) < 0.07,"AD-240 held tag share %.2f near expected %.2f" % [share,expected])
	t.check(baseline < biased,"AD-240 no-held baseline share is lower than biased")
	# No held artifacts: identical draws to the unbiased path (single randi after the roll).
	var run_state = _run(5,[])
	var settings: Dictionary = Artifacts.config()
	var hash_value := 5 * 7919 + 13
	var random := RandomNumberGenerator.new()
	random.seed = (hash_value ^ int(settings["seed_salt"])) & 0x7fffffff
	random.randf()
	var cands: Array = Artifacts.definitions().keys()
	cands.sort()
	var expect_id: String = cands[random.randi() % cands.size()]
	t.equal(str(Reward.artifact_choice(run_state,hash_value,true).get("id","")),expect_id,"AD-240 no-held draw sequence unchanged")

func _card_tag(t) -> void:
	var keys := _csv_keys()
	for i in 20:
		var card: Dictionary = Reward.artifact_choice(_run(i,[]),i+100,true)
		t.check(card.has("tag") and card["tag"] in TAGS,"AD-240 artifact card %d carries a tag" % i)
		t.equal(card["tag"],Artifacts.tag_of(str(card["id"])),"AD-240 card tag matches data %d" % i)
		t.check(keys.has("run.reward.artifact_tag_"+str(card["tag"])),"AD-240 card tag has a UI string %d" % i)

func _meta_unlocks(t) -> void:
	var locked: Array = Meta.locked_artifacts(Meta.empty_meta())
	for id in META_LOCKED:
		t.check(id in locked,"AD-240 %s locked by default" % id)
	var tuning: Dictionary = _tuning()
	for i in 80:
		var card: Dictionary = Reward.artifact_choice(_run(i,[]),i+500,true,locked)
		t.check(card.is_empty() or card["id"] not in locked,"AD-240 locked artifacts excluded from rewards %d" % i)
	var seen := {}
	for i in 400:
		var card: Dictionary = Reward.artifact_choice(_run(i,[]),i+900,true,[])
		seen[card["id"]] = true
	for id in META_LOCKED:
		t.check(seen.has(id),"AD-240 %s offered once unlocked" % id)
	t.check(not tuning.is_empty(),"AD-240 run tuning loads")
