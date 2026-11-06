extends Control
## AD-145: read-only Compendium (discovered runes/reactions/enemies/artifacts + milestones).
## The owner listens to back_requested; this screen never frees itself and never writes the profile.
const VisualTheme = preload("res://ui/pixel_theme.gd")
const MetaProgress = preload("res://world/meta_progress.gd")
const Artifacts = preload("res://world/artifacts.gd")
const RUN_PATH := "res://world/data/run_v2.json"
const TEXT := {
	"title": "compendium.title",
	"back": "compendium.back",
	"unknown": "compendium.unknown",
	"milestones": "compendium.milestones",
	"progress": "compendium.progress",
	"met": "compendium.met",
	"locked": "compendium.locked",
	"sections": {"runes": "compendium.section.runes", "reactions": "compendium.section.reactions", "enemies": "compendium.section.enemies", "artifacts": "compendium.section.artifacts"},
}
signal back_requested

var save_service = null
var section_labels := {}
var milestone_rows: Array = []
var back_button: Button
var _scroll: ScrollContainer

func _ready() -> void:
	VisualTheme.apply(self)
	if save_service == null:
		save_service = get_node_or_null("/root/SaveService")
	var meta: Dictionary = save_service.meta() if save_service != null else MetaProgress.empty_meta()
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	center.add_child(_scroll)
	var panel := VBoxContainer.new()
	panel.custom_minimum_size = Vector2(370, 0)
	panel.add_theme_constant_override("separation", 8)
	_scroll.add_child(panel)
	var heading := Label.new()
	heading.text = tr(TEXT["title"])
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(heading)
	var catalogs := catalogs_by_category()
	for cat in MetaProgress.categories():
		var found: Array = meta["discovered"][cat]
		var ids: Array = catalogs.get(cat, [])
		var seen := 0
		for id in ids:
			if id in found:
				seen += 1
		var header := Label.new()
		header.text = "%s %s" % [tr(TEXT["sections"][cat]), tr(TEXT["progress"]) % [seen, ids.size()]]
		panel.add_child(header)
		section_labels[cat] = header
		for id in ids:
			var entry := Label.new()
			entry.text = entry_name(cat, id) if id in found else tr(TEXT["unknown"])
			panel.add_child(entry)
	var ms_heading := Label.new()
	ms_heading.text = tr(TEXT["milestones"])
	panel.add_child(ms_heading)
	var counts := MetaProgress.counts(meta)
	var met := MetaProgress.milestones_met(meta)
	for ms in MetaProgress.milestones():
		var is_met: bool = str(ms["id"]) in met
		var have := mini(int(counts.get(ms["category"], 0)), int(ms["count"]))
		var row := Label.new()
		row.text = "%s %s %s" % [tr(ms["name_key"]), tr(TEXT["progress"]) % [have, int(ms["count"])], tr(TEXT["met"] if is_met else TEXT["locked"])]
		panel.add_child(row)
		milestone_rows.append({"id": str(ms["id"]), "label": row, "met": is_met, "progress": have, "target": int(ms["count"])})
	back_button = Button.new()
	back_button.text = tr(TEXT["back"])
	back_button.custom_minimum_size.y = 48
	back_button.focus_mode = Control.FOCUS_ALL
	panel.add_child(back_button)
	back_button.pressed.connect(func(): back_requested.emit())
	var director = get_node_or_null("/root/AudioDirector")
	if director != null:
		director.bind_button(back_button)
	visibility_changed.connect(_focus_first)
	_focus_first()

func _process(_delta: float) -> void:
	if _scroll != null:
		var h := get_viewport_rect().size.y - 16.0
		_scroll.custom_minimum_size = Vector2(390, minf(h, _scroll.get_child(0).get_combined_minimum_size().y))

func _focus_first() -> void:
	if is_visible_in_tree() and back_button != null:
		back_button.grab_focus()

func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		back_requested.emit()
		get_viewport().set_input_as_handled()

func entry_name(cat: String, id: String) -> String:
	match cat:
		"runes": return tr("rune." + id + ".name")
		"artifacts": return tr("artifact." + id + ".name")
		"reactions": return tr("compendium.reaction." + id)
		_: return tr("compendium.enemy." + id)

## Sorted id catalog per category.
static func catalogs_by_category() -> Dictionary:
	var compendium: Dictionary = MetaProgress.load_config().get("compendium", {})
	var runes := {}
	var file := FileAccess.open(RUN_PATH, FileAccess.READ)
	var run_cfg = JSON.parse_string(file.get_as_text()) if file != null else {}
	if run_cfg is Dictionary:
		for key in ["initial_unlocked", "reward_pool"]:
			for id in run_cfg.get(key, []):
				runes[id] = true
	for ms in MetaProgress.milestones():
		for id in ms.get("unlocks", {}).get("runes", []):
			runes[id] = true
	var rune_ids := runes.keys()
	rune_ids.sort()
	var artifact_ids := Artifacts.definitions().keys()
	artifact_ids.sort()
	return {
		"runes": rune_ids,
		"reactions": compendium.get("reactions", []),
		"enemies": compendium.get("enemies", []),
		"artifacts": artifact_ids,
	}
