extends RefCounted
## AD-170: the by-type trace index must behave exactly like the parent filter.
const Plain = preload("res://debug/debug_trace.gd")
const Indexed = preload("res://magic/runtime/indexed_trace.gd")
const KINDS := ["hit", "reaction", "status", "artifact", "missing"]

func _fill(trace) -> void:
	var seq := ["hit", "reaction", "status", "hit", "status", "reaction", "hit", "artifact"]
	for i in seq.size():
		trace.record(seq[i], {"cast_id": i % 3, "formula_id": "f%d" % (i % 2), "reason": "r%d" % i, "position": Vector2(i, 1), "tick": i})

func run(t) -> void:
	var plain = Plain.new(true)
	var idx = Indexed.new(true)
	_fill(plain)
	_fill(idx)
	t.equal(idx.to_json(), plain.to_json(), "snapshot json identical")
	for kind in KINDS:
		t.equal(idx.filter_records(-1, "", kind), plain.filter_records(-1, "", kind), "kind filter " + kind)
		t.equal(idx.filter_records(1, "", kind), plain.filter_records(1, "", kind), "cast+kind " + kind)
		t.equal(idx.filter_records(-1, "f1", kind), plain.filter_records(-1, "f1", kind), "formula+kind " + kind)
	t.equal(idx.filter_records(), plain.filter_records(), "unfiltered")
	t.equal(idx.filter_records(2, "f0"), plain.filter_records(2, "f0"), "cast+formula")
	t.equal(idx.count_of("hit"), 3, "count hit")
	t.equal(idx.count_of("missing"), 0, "count missing")
	t.equal(idx.records_since("status", 1), plain.filter_records(-1, "", "status").slice(1), "records_since")
	t.equal(idx.records_since("status", 5).size(), 0, "records_since past end")
	var got: Array = idx.filter_records(-1, "", "hit")
	got[0]["type"] = "mutated"
	t.equal(idx.filter_records(-1, "", "hit"), plain.filter_records(-1, "", "hit"), "returned copy is detached")
	idx.clear()
	t.equal(idx.count_of("hit"), 0, "clear empties index")
	t.equal(idx.filter_records(-1, "", "hit").size(), 0, "clear empties filter")
	var off = Indexed.new(false)
	_fill(off)
	t.equal(off.snapshot().size(), 0, "disabled stays empty")
	t.equal(off.count_of("hit"), 0, "disabled index empty")
