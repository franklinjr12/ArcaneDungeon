extends RefCounted

static var opener: Callable = Callable()

static func open_folder(path: String) -> void:
	if opener.is_valid():
		opener.call(path)
	elif DisplayServer.get_name() != "headless":
		OS.shell_open(path)
