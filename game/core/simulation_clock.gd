extends RefCounted
## TASK-008: deterministic fixed-tick service; isolated from rendering.
const DEFAULT_TICK_RATE := 60
var tick_rate: int
var tick := 0
var paused := false
var _accumulator := 0.0
var _rng := RandomNumberGenerator.new()
var _seed := 0
var _id_counters: Dictionary = {}

func _init(run_seed: int = 1, ticks_per_second: int = DEFAULT_TICK_RATE) -> void:
	tick_rate = maxi(1,ticks_per_second)
	reset(run_seed)

func reset(run_seed: int) -> void:
	_seed = run_seed
	_rng.seed = run_seed
	tick = 0
	_accumulator = 0.0
	_id_counters.clear()
	paused = false

func advance(delta: float) -> int:
	if paused or delta <= 0:
		return 0
	_accumulator += delta
	var step := 1.0 / float(tick_rate)
	var count := mini(240,int(floor((_accumulator + 0.000000001) / step)))
	tick += count
	_accumulator -= float(count) * step
	return count

func step_once() -> int:
	# The explicit debugger step works even while paused.
	tick += 1
	return tick

func set_paused(value: bool) -> void:
	paused = value

func next_id(domain: String) -> int:
	_id_counters[domain] = int(_id_counters.get(domain,0)) + 1
	return _id_counters[domain]

func random_int(minimum: int, maximum: int) -> int:
	return _rng.randi_range(minimum,maximum)

func seed_value() -> int:
	return _seed

func order_targets(targets: Array, origin: Vector2) -> Array:
	var ordered := targets.duplicate(true)
	ordered.sort_custom(func(a,b):
		var da: float = Vector2(a["x"],a["y"]).distance_squared_to(origin)
		var db: float = Vector2(b["x"],b["y"]).distance_squared_to(origin)
		if absf(da-db) < 0.0000001:
			return int(a["id"]) < int(b["id"])
		return da < db
	)
	return ordered

func normalized_state() -> Dictionary:
	return {"tick":tick,"seed":_seed,"ids":_id_counters.duplicate(true)}
