extends RefCounted
## Minimal persistent error log for loader/navigation and future subsystem diagnostics.
const PATH := "user://arcane_errors.log"

static func record(code: String, message: String) -> void:
	var file := FileAccess.open(PATH, FileAccess.READ_WRITE)
	if file == null:
		file = FileAccess.open(PATH, FileAccess.WRITE)
	if file == null:
		printerr("%s: %s" % [code, message])
		return
	file.seek_end()
	file.store_line("%s | %s | %s" % [Time.get_datetime_string_from_system(), code, message])
	file.close()
	printerr("%s: %s" % [code, message])
