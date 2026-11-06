extends Node
## AD-020: AudioDirector. Cue table + voice limits; silent stubs when streams are missing.
## AD-082: telegraph cues duck Ambience + non-telegraph SFX (SFXBed sub-bus) by DUCK_DB via
## AudioEffectAmplify, never touching bus volume_db (owned by user settings).
## See GDD §12 (audio) and Tech Outline §3/§5. Audio never affects the simulation.
const ErrorLog = preload("res://game/core/error_log.gd")
const CUES_FILE := "res://game/audio/audio_cues_v1.json"

const DUCK_DB := -6.0
const DUCK_BUSES := ["Ambience", "SFXBed", "Music"]
const BED_BUS := "SFXBed"
const DUCK_MIN_SEC := 0.25

signal cue_played(cue_id: String, pos, played: bool)

var table: Dictionary = {}
var voices: Array = []
var _warned: Dictionary = {}
var _overrides: Dictionary = {}
var _serial := 0
var _duck_left := 0.0
var music_context := ""
var music_fade_in := 1.0
var music_fade_out := 0.0
var _music_prev := ""
var _music_t := 0.0
var _music_from_in := 0.0
var _music_from_out := 0.0
var _music_players: Dictionary = {}

func _init() -> void:
	var f := FileAccess.open(CUES_FILE, FileAccess.READ)
	if f == null:
		return
	var json := JSON.new()
	if json.parse(f.get_as_text()) == OK and typeof(json.data) == TYPE_DICTIONARY:
		load_table(json.data)

func _ready() -> void:
	var svc = get_node_or_null("/root/SaveService")
	if svc != null and svc.get("settings") != null:
		svc.settings.apply_audio()

func load_table(data: Dictionary) -> void:
	table = data if typeof(data.get("cues")) == TYPE_DICTIONARY else {}
	if typeof(data.get("music")) == TYPE_DICTIONARY:
		table["music"] = data["music"]
	if typeof(data.get("events")) == TYPE_DICTIONARY:
		table["events"] = data["events"]

## AD-151: event key -> cue id map from the data file; no Node instance needed (cached).
static var _events_cache: Dictionary = {}
static func load_events() -> Dictionary:
	if _events_cache.is_empty():
		var f := FileAccess.open(CUES_FILE, FileAccess.READ)
		if f != null:
			var json := JSON.new()
			if json.parse(f.get_as_text()) == OK and typeof(json.data) == TYPE_DICTIONARY \
					and typeof(json.data.get("events")) == TYPE_DICTIONARY:
				_events_cache = json.data["events"]
	return _events_cache

func event_keys() -> Array:
	return (table.get("events", {}) as Dictionary).keys()

## Cue id for a gameplay event key ("reaction:wet_cold_freeze"), or "" (warned once) when unmapped.
func cue_for_event(key: String) -> String:
	var events: Dictionary = table.get("events", {})
	if events.has(key):
		return str(events[key])
	_warn_once("event:" + key, "no cue for event")
	return ""

func register_stream(cue_id: String, stream: AudioStream) -> void:
	_overrides[cue_id] = stream

func _warn_once(cue_id: String, msg: String) -> void:
	if _warned.has(cue_id):
		return
	_warned[cue_id] = true
	ErrorLog.record("AUDIO_STREAM_MISSING", cue_id + " -> " + msg)

func _resolve_stream(cue_id: String, path: String) -> AudioStream:
	if _overrides.has(cue_id):
		return _overrides[cue_id]
	if path == "" or not ResourceLoader.exists(path):
		return null
	return load(path) as AudioStream

## Primary path if it exists, else the optional placeholder (logged once per id), else "".
func resolve_path(id: String, cfg: Dictionary) -> String:
	var path := str(cfg.get("stream", ""))
	if path != "" and ResourceLoader.exists(path):
		return path
	var ph := str(cfg.get("placeholder", ""))
	if ph != "" and ResourceLoader.exists(ph):
		if not _warned.has("ph:" + id):
			_warned["ph:" + id] = true
			ErrorLog.record("AUDIO_PLACEHOLDER", id + " -> " + ph)
		return ph
	_warn_once(id, path)
	return ""

## Hover + press feedback for a UI button; output-only.
func bind_button(button: BaseButton, press_cue: String = "ui.confirm") -> void:
	button.mouse_entered.connect(play.bind("ui.hover"))
	button.pressed.connect(play.bind(press_cue))

func play(cue_id: String, pos = null) -> bool:
	var ok := _play(cue_id, pos)
	cue_played.emit(cue_id, pos, ok)
	return ok

func _play(cue_id: String, pos) -> bool:
	if cue_id.begins_with("music."):
		return set_music_context(cue_id.trim_prefix("music."))
	var cues: Dictionary = table.get("cues", {})
	if not cues.has(cue_id):
		_warn_once(cue_id, "unknown cue")
		return false
	var cue: Dictionary = cues[cue_id]
	var stream: AudioStream = _overrides.get(cue_id)
	if stream == null:
		var path := resolve_path(cue_id, cue)
		stream = load(path) as AudioStream if path != "" else null
	if stream == null:
		return false
	var prio := int(cue.get("priority", 1))
	var unstealable := int(table.get("unstealable_priority", 3))
	var same: Array = voices.filter(func(v): return v["cue_id"] == cue_id)
	if same.size() >= int(cue.get("max_voices", 1)):
		if not _steal(same, prio, unstealable):
			return false
	if voices.size() >= int(table.get("max_voices_total", 24)):
		if not _steal(voices, prio, unstealable):
			return false
	_serial += 1
	var voice := {"cue_id": cue_id, "priority": prio, "serial": _serial, "player": null}
	if is_inside_tree() and DisplayServer.get_name() != "headless":
		var p: Node = AudioStreamPlayer2D.new() if pos is Vector2 else AudioStreamPlayer.new()
		p.stream = stream
		p.bus = route_bus(cue)
		if pos is Vector2:
			p.position = pos
		p.finished.connect(release_voice.bind(_serial))
		add_child(p)
		p.play()
		voice["player"] = p
	voices.append(voice)
	if is_telegraph(cue):
		duck_for(maxf(stream.get_length(), DUCK_MIN_SEC))
	return true

func is_telegraph(cue: Dictionary) -> bool:
	return int(cue.get("priority", 1)) >= int(table.get("unstealable_priority", 3))

## Non-telegraph SFX go through the SFXBed sub-bus (sends to SFX) so they can be ducked.
func route_bus(cue: Dictionary) -> String:
	var bus := str(cue.get("bus", "SFX"))
	if bus == "SFX" and not is_telegraph(cue) and AudioServer.get_bus_index(BED_BUS) >= 0:
		return BED_BUS
	return bus

func duck_for(sec: float) -> void:
	_duck_left = maxf(_duck_left, sec)
	_apply_duck(DUCK_DB)

func is_ducking() -> bool:
	return _duck_left > 0.0

func _music_cfg() -> Dictionary:
	var m = table.get("music", {})
	return m if typeof(m) == TYPE_DICTIONARY else {}

func music_stream_path(ctx: String) -> String:
	var c: Dictionary = _music_cfg().get("contexts", {})
	if not c.has(ctx):
		return ""
	return resolve_path("music." + ctx, c[ctx])

func set_music_context(ctx: String) -> bool:
	var c: Dictionary = _music_cfg().get("contexts", {})
	if not c.has(ctx):
		_warn_once("music." + ctx, "unknown music context")
		return false
	if ctx == music_context:
		return true
	# Gains continue from where they are, so there is no pop. An older outgoing context is dropped
	# unless it is the one coming back.
	_music_from_in = music_fade_out if ctx == _music_prev else 0.0
	_music_from_out = music_fade_in if music_context != "" else 0.0
	_music_prev = music_context
	music_context = ctx
	music_fade_in = _music_from_in
	music_fade_out = _music_from_out
	_music_t = 0.0
	var tmp = _music_players.get("in")
	_music_players["in"] = _music_players.get("out")
	_music_players["out"] = tmp
	_music_apply()
	return true

func music_step(delta: float) -> void:
	if _music_prev == "" and music_fade_in >= 1.0:
		return
	var dur := maxf(float(_music_cfg().get("crossfade_sec", 1.5)), 0.001)
	_music_t = minf(_music_t + delta, dur)
	var k := _music_t / dur
	music_fade_in = lerpf(_music_from_in, 1.0, k)
	music_fade_out = lerpf(_music_from_out, 0.0, k)
	if k >= 1.0:
		_music_prev = ""
	_music_apply()

func _music_apply() -> void:
	_music_player("in", music_context, music_fade_in)
	_music_player("out", _music_prev, music_fade_out)

func _music_player(slot: String, ctx: String, gain: float) -> void:
	if not is_inside_tree() or DisplayServer.get_name() == "headless":
		return
	var p: AudioStreamPlayer = _music_players.get(slot)
	if p == null:
		p = AudioStreamPlayer.new()
		p.bus = str(_music_cfg().get("bus", "Music"))
		add_child(p)
		_music_players[slot] = p
	if ctx == "":
		p.stop()
		return
	var path := music_stream_path(ctx)
	if path == "":
		p.stop()
		return
	var cur: AudioStream = p.stream
	if cur == null or p.get_meta("ctx", "") != ctx:
		var st := (load(path) as AudioStream).duplicate() as AudioStream
		if st is AudioStreamWAV:
			st.loop_mode = AudioStreamWAV.LOOP_FORWARD
			st.loop_end = int(st.get_length() * st.mix_rate)
		elif st is AudioStreamOggVorbis:
			st.loop = true
		p.stream = st
		p.set_meta("ctx", ctx)
		p.play()
	p.volume_db = linear_to_db(maxf(gain, 0.0001))

func _process(delta: float) -> void:
	music_step(delta)
	if _duck_left <= 0.0:
		return
	_duck_left -= delta
	if _duck_left <= 0.0:
		_duck_left = 0.0
		_apply_duck(0.0)

func _amp(bus: String) -> AudioEffectAmplify:
	var idx := AudioServer.get_bus_index(bus)
	if idx < 0 or AudioServer.get_bus_effect_count(idx) <= 0:
		return null
	return AudioServer.get_bus_effect(idx, 0) as AudioEffectAmplify

func _apply_duck(db: float) -> void:
	for bus in DUCK_BUSES:
		var a := _amp(bus)
		if a != null:
			a.volume_db = db

## Probe helper: current duck amount (dB) on a bus; 0.0 when it has no Amplify.
func duck_db(bus: String) -> float:
	var a := _amp(bus)
	return a.volume_db if a != null else 0.0

## Steal the oldest lowest-priority stealable voice from candidates.
func _steal(candidates: Array, prio: int, unstealable: int) -> bool:
	var best = null
	for v in candidates:
		if v["priority"] >= unstealable or v["priority"] > prio:
			continue
		if best == null or v["priority"] < best["priority"] \
				or (v["priority"] == best["priority"] and v["serial"] < best["serial"]):
			best = v
	if best == null:
		return false
	release_voice(best["serial"])
	return true

func release_voice(serial: int) -> void:
	for i in voices.size():
		if voices[i]["serial"] == serial:
			var p = voices[i]["player"]
			if p != null and is_instance_valid(p):
				p.stop()
				p.queue_free()
			voices.remove_at(i)
			return
