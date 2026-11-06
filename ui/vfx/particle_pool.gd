extends RefCounted
## AD-149 fixed-capacity CPU particle pool. Preallocated once; emit() drops when full, so it never grows past the cap.
## Free slots are handed out lowest-index first, so identical emit/step sequences give identical layouts.
var _cap := 0
var _pos := PackedVector2Array()
var _vel := PackedVector2Array()
var _age := PackedInt32Array()
var _life := PackedInt32Array()
var _size := PackedFloat32Array()
var _col := PackedColorArray()
var _col_end := PackedColorArray()
var _live := PackedByteArray()
var _free := PackedInt32Array()
var _active := 0

func _init(cap: int = 0) -> void:
	_cap = maxi(0, cap)
	_pos.resize(_cap)
	_vel.resize(_cap)
	_age.resize(_cap)
	_life.resize(_cap)
	_size.resize(_cap)
	_col.resize(_cap)
	_col_end.resize(_cap)
	_live.resize(_cap)
	_free.resize(_cap)
	_reset_free()

func _reset_free() -> void:
	_free.resize(_cap)
	for i in _cap:
		_free[i] = _cap - 1 - i  # stack top (last element) is the lowest index
	_active = 0

func capacity() -> int:
	return _cap

func active_count() -> int:
	return _active

func emit(at: Vector2, vel: Vector2, life: int, size: float, color: Color, color_end: Color) -> bool:
	if _active >= _cap or life <= 0:
		return false
	var i := _take()
	_pos[i] = at
	_vel[i] = vel
	_age[i] = 0
	_life[i] = life
	_size[i] = size
	_col[i] = color
	_col_end[i] = color_end
	_live[i] = 1
	return true

func _take() -> int:
	var i: int = _free[_free.size() - 1]
	_free.resize(_free.size() - 1)
	_active += 1
	return i

## Advance one tick: integrate, age, recycle dead slots (ascending index).
func step() -> void:
	var freed: Array = []
	for i in _cap:
		if _live[i] == 0:
			continue
		_pos[i] += _vel[i]
		_age[i] += 1
		if _age[i] >= _life[i]:
			_live[i] = 0
			freed.append(i)
	if freed.is_empty():
		return
	# Keep the free stack ordered (descending) so the lowest free index is always taken first.
	var all: Array = Array(_free)
	all.append_array(freed)
	all.sort_custom(func(a, b): return a > b)
	_free = PackedInt32Array(all)
	_active -= freed.size()

func clear() -> void:
	_live.fill(0)
	_reset_free()

func is_live(i: int) -> bool:
	return i >= 0 and i < _cap and _live[i] == 1

func position_of(i: int) -> Vector2:
	return _pos[i]

func size_of(i: int) -> float:
	return _size[i]

func progress_of(i: int) -> float:
	return float(_age[i]) / float(maxi(1, _life[i]))

## Colour lerped start->end over life, alpha fading to zero at death.
func color_of(i: int) -> Color:
	var p := progress_of(i)
	var c: Color = _col[i].lerp(_col_end[i], p)
	c.a *= 1.0 - p
	return c
