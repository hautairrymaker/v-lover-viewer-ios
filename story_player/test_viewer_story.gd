extends SceneTree

var checks: Array = []
var viewer: Node

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, identity: String) -> void:
	checks.append({"id":identity, "ok":ok})
	if not ok: printerr("FAILED ", identity)

func wait_message(host: Control) -> bool:
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < 15000:
		if is_instance_valid(host.story_root) and host.story_root.message_active: return true
		await process_frame
	return false

func run() -> void:
	viewer = load("res://main.gd").new()
	root.add_child(viewer)
	await process_frame
	await process_frame
	check(viewer.mode.item_count == 5, "five_viewer_modes")
	viewer.mode.select(4)
	await viewer._load_selection()
	await process_frame
	var host: Control = viewer.story_host
	check(is_instance_valid(host), "story_mode_opens")
	check(not host.phone_root.has_node("MainMenu"), "no_extra_start_menu")
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/gallery.json"))
	var eligible: Array = source.cards.filter(func(card): return card.get("playable", false) and host.scenario.labels.has("*" + str(card.label).trim_prefix("*")))
	check(host.reading_cards.size() == eligible.size() + 1, "public_chapters_and_intro")
	check(host.chapter_list.item_count == host.reading_cards.size(), "all_chapters_selectable")
	check(not viewer.stage.visible and not viewer.viewer_sidebar.visible, "model_controls_hidden")
	check(not viewer.mode.disabled, "mode_navigation_accessible")
	host.play_button.pressed.emit()
	check(await wait_message(host), "intro_reaches_real_dialogue")
	if not is_instance_valid(host.story_root):
		print("VIEWER_STORY_TEST input_failed ", JSON.stringify(checks))
		viewer.mode.select(2)
		await viewer._load_selection()
		viewer.ui.free()
		viewer.voice_player.free()
		viewer.free()
		quit(1)
		return
	var player: Control = host.story_root
	check(player.playback_controls.visible, "original_playback_controls")
	player.set_auto_play(true)
	player.set_skip_play(true)
	check(player.auto_play and player.skip_play, "auto_and_fast_work")
	player.set_skip_play(false)
	player.set_auto_play(false)
	check(host._save_reading(), "reading_save")
	await host._return_to_menu()
	await process_frame
	check(host.phone_root.visible and host.story_root == null, "return_to_chapters")
	await host._load_save_path(host.AUTO_SAVE)
	check(await wait_message(host), "resume_saved_dialogue")
	check(not host.story_root.auto_play and not host.story_root.skip_play, "restored_controls")
	await host._return_to_menu()
	await process_frame
	for index in range(1, host.reading_cards.size()):
		host._open_chapter(index)
		check(await wait_message(host), "chapter_entry_%02d" % index)
		await host._return_to_menu()
		await process_frame
	host._open_chapter(0)
	check(await wait_message(host), "intro_after_all_entries")
	viewer.mode.select(2)
	await viewer._load_selection()
	await process_frame
	check(viewer.story_host == null and viewer.story_container == null, "story_viewport_released")
	check(viewer.stage.visible and viewer.viewer_sidebar.visible, "viewer_restored")
	check(viewer.pictures.size() > 0, "portrait_mode_preserved")
	viewer.mode.select(4)
	await viewer._load_selection()
	await process_frame
	check(is_instance_valid(viewer.story_host), "story_mode_reentry")
	await viewer.story_host.deactivate()
	viewer.mode.select(2)
	await viewer._load_selection()
	await process_frame
	var failed := checks.filter(func(entry): return not entry.ok)
	var result := {"checks":checks, "passed":checks.size()-failed.size(),
		"total":checks.size(), "failed":failed.size()}
	var path := OS.get_environment("VIEWER_STORY_TEST_RESULT")
	if path != "": FileAccess.open(path, FileAccess.WRITE).store_string(JSON.stringify(result, "\t"))
	print("VIEWER_STORY_TEST ", JSON.stringify(result))
	viewer.ui.free()
	viewer.voice_player.free()
	viewer.free()
	quit(0 if failed.is_empty() else 1)
