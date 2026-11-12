extends RefCounted
## AD-232: every font referenced by UI/theme code, UI layouts or the art manifest has a licence entry in assets/ui/ad_ui_kit.json.
const MANIFEST := "res://art/export/manifest.json"
const KIT := "res://assets/ui/ad_ui_kit.json"
const FONT_NAME := "arc_fnt_[a-z0-9_]+"
const SCAN_DIRS := ["res://ui", "res://assets/ui/layouts"]

func _load_json(path: String):
	return JSON.parse_string(FileAccess.get_file_as_string(path))

## Font stem -> first file that names it, from UI scripts and layout JSON.
func _referenced_fonts() -> Dictionary:
	var found := {}
	var regex := RegEx.create_from_string(FONT_NAME)
	for dir in SCAN_DIRS:
		for filename in DirAccess.get_files_at(dir):
			if not (filename.ends_with(".gd") or filename.ends_with(".json")):
				continue
			var path: String = dir + "/" + filename
			for match in regex.search_all(FileAccess.get_file_as_string(path)):
				found[match.get_string()] = path
	return found

func run(t) -> void:
	var manifest = _load_json(MANIFEST)
	var kit = _load_json(KIT)
	t.check(manifest is Dictionary and kit is Dictionary, "AD-232 manifest and ad_ui_kit parse")
	if not (manifest is Dictionary and kit is Dictionary):
		return
	var licences = kit.get("font_licences", {})
	t.check(licences is Dictionary, "AD-232 ad_ui_kit.json has font_licences")
	if not (licences is Dictionary):
		return
	var required := {}
	for stem in manifest["assets"]:
		if str(manifest["assets"][stem].get("category", "")) == "fnt":
			required[stem] = "art/export/manifest.json"
	var referenced := _referenced_fonts()
	for stem in referenced:
		required[stem] = referenced[stem]
	t.check(required.size() > 0, "AD-232 font references discovered")
	for stem in required:
		var entry = licences.get(stem, {})
		var licensed: bool = entry is Dictionary and str(entry.get("licence", "")) != ""
		t.check(licensed, "AD-232 font %s (%s) has a licence in ad_ui_kit.json" % [stem, required[stem]])
	t.check(not manifest["assets"].has("arc_fnt_digits_3x5"), "AD-232 unlicensed digits font removed from manifest")
