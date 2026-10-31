extends RefCounted
## AD-067: four-bus settings defaults + reusable settings screen persistence.
const Service = preload("res://game/core/save_service.gd")
const Screen = preload("res://ui/settings_screen.gd")
const DIR := "user://ad067_test/"

func _clean() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	for f in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR + f)

func run(t) -> void:
	_clean()
	var svc = Service.new()
	svc.set_base_dir(DIR)
	for bus in ["Master", "SFX", "Ambience", "UI"]:
		t.equal(svc.settings.volumes[bus], 1.0, "AD-067 default volume " + bus)
	t.check(not svc.settings.telemetry_opt_in, "AD-067 telemetry default off")
	var screen = Screen.new()
	screen.save_service = svc
	(Engine.get_main_loop() as SceneTree).root.add_child(screen)
	var keys: Array = screen.volume_sliders.keys()
	keys.sort()
	t.equal(keys, ["Ambience", "Master", "SFX", "UI"], "AD-067 one slider per bus")
	t.check(screen.flash_toggle != null and screen.shake_toggle != null and screen.telemetry_toggle != null, "AD-067 toggles exist")
	t.check(not screen.flash_toggle.button_pressed and not screen.shake_toggle.button_pressed and not screen.telemetry_toggle.button_pressed, "AD-067 toggles start unpressed")
	screen.volume_sliders["SFX"].value = 0.35
	screen.flash_toggle.button_pressed = true
	screen.shake_toggle.button_pressed = true
	screen.telemetry_toggle.button_pressed = true
	var svc2 = Service.new()
	svc2.set_base_dir(DIR)
	t.equal(svc2.settings.volumes["SFX"], 0.35, "AD-067 SFX persists across restart")
	t.check(svc2.settings.reduce_flashes, "AD-067 reduce_flashes persists")
	t.check(not svc2.settings.screen_shake, "AD-067 reduce shake stored as screen_shake=false")
	t.check(svc2.settings.telemetry_opt_in, "AD-067 telemetry opt-in persists")
	var hits := []
	screen.back_requested.connect(func(): hits.append(1))
	screen.back_button.pressed.emit()
	t.equal(hits.size(), 1, "AD-067 back button emits back_requested")
	screen.free()
	svc2.free()
	svc.free()
	_clean()
	DirAccess.remove_absolute(DIR)
