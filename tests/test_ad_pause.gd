extends RefCounted
## AD-068: modal pause menu behaviour (standalone, no run needed).
const Pause = preload("res://ui/pause_menu.gd")

func run(t) -> void:
	var menu = Pause.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(menu)
	for n in ["ResumeButton", "SettingsButton", "RetryButton", "QuitButton", "ConfirmButton", "CancelButton"]:
		t.check(menu.find_child(n, true, false) is Button, "AD-068 pause has " + n)
	for k in Pause.TEXT:
		t.check(String(Pause.TEXT[k]) != "", "AD-068 pause text " + k)
	var quits := [0]
	var retries := [0]
	var resumes := [0]
	menu.quit_confirmed.connect(func(): quits[0] += 1)
	menu.retry_confirmed.connect(func(): retries[0] += 1)
	var saves := [0]
	menu.save_quit_confirmed.connect(func(): saves[0] += 1)
	t.check(not menu.save_quit_button.visible, "AD-146 save&quit hidden by default")
	menu.set_save_available(true)
	t.check(menu.save_quit_button.visible, "AD-146 save&quit shown when available")
	menu.request_save_quit()
	t.check(menu.is_confirm_open(), "AD-146 save&quit asks for confirmation")
	menu.confirm_pending()
	t.equal(saves[0], 1, "AD-146 save&quit emitted on confirm")
	t.equal(quits[0], 0, "AD-146 save&quit does not emit quit")
	menu.resume_requested.connect(func(): resumes[0] += 1)
	menu.request_quit()
	t.check(menu.is_confirm_open() and not menu.panel.visible, "AD-068 quit shows confirm")
	t.equal(quits[0], 0, "AD-068 quit not emitted before confirm")
	menu.confirm_pending()
	t.equal(quits[0], 1, "AD-068 quit emitted once on confirm")
	menu.confirm_pending()
	t.equal(quits[0], 1, "AD-068 confirm without pending emits nothing")
	menu.cancel_confirm()
	t.check(not menu.is_confirm_open() and menu.panel.visible, "AD-068 cancel hides confirm")
	menu.request_retry()
	menu.confirm_pending()
	t.equal(retries[0], 1, "AD-068 retry emitted on confirm")
	t.equal(quits[0], 1, "AD-068 retry does not emit quit")
	menu.cancel_confirm()
	menu.open_settings()
	t.check(menu.is_settings_open() and not menu.panel.visible, "AD-068 settings opens")
	t.check(menu.settings_screen.volume_sliders.size() == 4, "AD-068 settings has volume sliders")
	menu.request_quit()
	menu.handle_cancel()
	t.check(not menu.is_settings_open() and menu.is_confirm_open(), "AD-068 cancel closes settings first")
	menu.handle_cancel()
	t.check(not menu.is_confirm_open(), "AD-068 cancel then closes confirm")
	t.equal(resumes[0], 0, "AD-068 no resume yet")
	menu.handle_cancel()
	t.equal(resumes[0], 1, "AD-068 cancel with nothing open resumes")
	menu.queue_free()
