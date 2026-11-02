extends Node
## AD-020: AudioDirector. Cue table + voice limits; silent stubs when streams are missing.
## AD-082: telegraph cues duck Ambience + non-telegraph SFX (SFXBed sub-bus) by DUCK_DB via
## AudioEffectAmplify, never touching bus volume_db (owned by user settings).
## See GDD §12 (audio) and Tech Outline §3/§5. Audio never affects the simulation.
const ErrorLog = preload("res://game/core/error_log.gd")
const CUES_FILE := "res://game/audio/audio_cues_v1.json"

const DUCK_DB := -6.0
const DUCK_BUSES := ["Ambience", "SFXBed"]
const BED_BUS := "SFXBed"
const DUCK_MIN_SEC := 0.25

signal cue_played(cue_id: String, pos, played: bool)

var table: Dictionary = {}
var voices: Array = []
var _warned: Dictionary = {}
var _overrides: Dictionary = {}
var _serial := 0
var _duck_left := 0.0

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

## Hover + press feedback for a UI button; output-only.
func bind_button(button: BaseButton, press_cue: String = "ui.confirm") -> void:
	button.mouse_entered.connect(play.bind("ui.hover"))
	button.pressed.connect(play.bind(press_cue))

func play(cue_id: String, pos = null) -> bool:
	var ok := _play(cue_id, pos)
	cue_played.emit(cue_id, pos, ok)
	return ok

func _play(cue_id: String, pos) -> bool:
	var cues: Dictionary = table.get("cues", {})
	if not cues.has(cue_id):
		_warn_once(cue_id, "unknown cue")
		return false
	var cue: Dictionary = cues[cue_id]
	var path := str(cue.get("stream", ""))
	var stream := _resolve_stream(cue_id, path)
	if stream == null:
		_warn_once(cue_id, path)
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

func _process(delta: float) -> void:
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
