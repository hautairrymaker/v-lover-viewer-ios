extends SceneTree

var checks: Array = []
var host: Control

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, identity: String) -> void:
	checks.append({"id":identity, "ok":ok})
	if not ok: printerr("FAILED ", identity)

func wait_message(limit := 15.0) -> bool:
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < limit * 1000:
		if is_instance_valid(host.story_root) and host.story_root.message_active: return true
		await process_frame
	return false

func run() -> void:
	host = load("res://scripts/story_player_host.gd").new()
	root.add_child(host)
	await process_frame
	check(host.reading_cards.size() == host.scenario.labels.size(), "all_labels_unlocked")
	check(not ResourceLoader.has_cached("res://scripts/game.gd"), "no_full_game_host")
	check(not ResourceLoader.has_cached("res://scripts/schedule_flow.gd"), "no_schedule_model")
	var menu: Control = host.phone_root.get_node("MainMenu")
	check(menu.size.x > 0 and menu.size.y > 0, "menu_has_visible_area")
	var gallery_button: Control = menu.actions.get_node("MainGallery")
	var hit: Rect2 = gallery_button.get_global_rect()
	check(root.get_visible_rect().intersects(hit), "gallery_button_on_screen")
	host._show_gallery(menu)
	var gallery: Control = menu.get_node("Gallery")
	check(gallery.cards.size() == host.reading_cards.size(), "gallery_all_chapters")
	gallery.set_page(1000)
	check(gallery.page == ceili(gallery.cards.size() / 6.0) - 1, "gallery_last_page")
	gallery.set_page(-1000)
	gallery.closed.emit()
	await process_frame
	host._play_label("開場劇情")
	check(await wait_message(), "real_intro_reaches_dialogue")
	var player: Control = host.story_root
	check(not host.phone_root.visible and player.visible, "player_shown")
	check(player.playback_controls.visible, "playback_controls")
	check(player.story_terms.size() > 0, "story_terms_loaded")
	check(not player.portrait_stage.definitions.is_empty(), "portrait_variants_loaded")
	check(player.cg_stage.catalog.size() == 25, "cg_catalog_loaded")
	player.set_auto_play(true)
	player.set_skip_play(true)
	check(player.auto_play and player.skip_play, "auto_and_skip_controls")
	player.set_auto_play(false)
	player.set_skip_play(false)
	player.hide_dialogue()
	check(player.dialogue_hidden and player.presentation_paused, "hide_dialogue_pauses")
	player.restore_dialogue()
	check(not player.dialogue_hidden and not player.presentation_paused, "restore_dialogue")
	player.open_backlog()
	check(player.backlog.visible and player.presentation_paused, "history_opens")
	player.backlog.close_view()
	check(not player.backlog.visible and not player.presentation_paused, "history_closes")
	var voice_path: String = player.assets.voice.values()[0]
	check(player._load_audio(voice_path) != null, "voice_resource_decodes")
	player.presentation_paused = true
	player.voice_player.stream_paused = true
	check(player.save_to_file("user://story_quick_save.json"), "manual_save")
	var saved: Dictionary = player.save_state()
	check(not saved.is_empty() and not saved.has("management"), "reading_save_no_management")
	var cursor: int = saved.main.idx
	await host._return_to_menu()
	check(host.story_root == null and host.phone_root.visible, "return_menu")
	await process_frame
	await host._load_save_path("user://story_quick_save.json")
	check(is_instance_valid(host.story_root), "load_reading")
	player = host.story_root
	check(player.gallery_replay, "loaded_reading_side_effects_disabled")
	check(player.idx == cursor + 1 and player.main_context.pending.index == cursor,
		"restored_cursor")
	check(await wait_message(), "restored_dialogue_runs")
	check(player.option_menu.buttons.save.disabled == false, "save_enabled")
	var old_id := player.get_instance_id()
	FileAccess.open("user://broken_progress.json", FileAccess.WRITE).store_string("{")
	await host._load_save_path("user://broken_progress.json")
	check(host.story_root.get_instance_id() == old_id, "corrupt_save_preserves_player")
	var file := FileAccess.open("user://invalid_progress.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"version":-1}))
	file.close()
	await host._load_save_path("user://invalid_progress.json")
	check(host.story_root.get_instance_id() == old_id, "invalid_schema_preserves_player")
	host._show_settings(player.option_menu)
	check(player.option_menu.has_node("Settings"), "settings_open")
	player.option_menu.get_node("Settings").queue_free()
	await process_frame
	player.open_save_slots(true)
	check(is_instance_valid(player.save_slots), "save_slots_open")
	player.save_slots.closed.emit()
	await process_frame
	check(not is_instance_valid(player.save_slots), "save_slots_close")
	check(host._save_reading(), "automatic_progress_save")
	await host._return_to_menu()
	await process_frame
	for actor in ["idol1", "idol2", "idol3"]:
		var found := ""
		for label in host.chapter_contexts:
			if host.chapter_contexts[label].actor == actor:
				found = label
				break
		check(found != "", "caller_context_found_" + actor)
		if found == "": continue
		host._play_label(found)
		check(host.story_root.initial_background == host.chapter_contexts[found].background,
			"caller_background_assigned_" + actor)
		check(await wait_message(), "caller_dialogue_reaches_message_" + actor)
		check(host.story_root.bg_sprite.texture != null, "caller_background_visible_" + actor)
		await host._return_to_menu()
		await process_frame
	var fixture: Control = host._new_player()
	fixture.ops = [{"op":"selection", "choice":"A", "label":"A"},
		{"op":"selection", "choice":"B", "label":"B"}, {"op":"endscenario"}]
	fixture.labels = {"*A":2, "*B":2}
	var context: Dictionary = fixture._context("main", 1)
	fixture._selection_block(fixture.ops[0], context)
	await process_frame
	check(fixture.choice_box.visible and fixture.choice_box.get_child_count() == 2,
		"interactive_choices_visible")
	fixture.choice_box.get_child(1).pressed.emit()
	await process_frame
	check(context.idx == 2 and not fixture.choice_box.visible, "choice_jump")
	fixture.ops = [{"op":"wait", "time":"0.01"}, {"op":"endthread"}]
	fixture.labels = {"*Worker":0}
	fixture._start_subthread("Worker")
	await fixture._wait_threads()
	check(not fixture._any_alive(), "thread_wait_completes")
	await fixture.close_scene()
	fixture.queue_free()
	var ending: Control = host._new_player()
	host.story_root = ending
	host._set_reading(true)
	ending.ops = [{"op":"endscenario"}]
	ending.idx = 0
	await ending._run()
	await ending._finish_playback()
	check(host.story_root == null and host.phone_root.visible, "natural_completion_returns")
	await process_frame
	# Load every supplied native actor through the actual engine extensions.
	var stage: Node2D = load("res://scripts/live2d_stage.gd").new()
	root.add_child(stage)
	for actor in ["井上早苗", "日向純子", "黑沼唯"]:
		stage.show_character(actor, actor, "", "Action_1")
		stage.model.advance(0.05)
		check(is_instance_valid(stage.model) and stage.model.get_parameters().size() > 0,
			"live2d_" + str(stage.loads))
		stage.clear_character()
	stage.queue_free()
	var cg: Node2D = load("res://scripts/story_cg_stage.gd").new()
	root.add_child(cg)
	var index := 0
	for actor in cg.catalog:
		index += 1
		var definition: Dictionary = cg.catalog[actor]
		check(cg.show_character(actor, definition.default_state), "spine_group_" + str(index))
		await process_frame
		cg.clear_character()
	cg.queue_free()
	host.queue_free()
	await process_frame
	await create_timer(0.25).timeout
	var failed := checks.filter(func(item): return not item.ok)
	var out := OS.get_environment("PLAYER_TEST_RESULT")
	if out != "":
		FileAccess.open(out, FileAccess.WRITE).store_string(JSON.stringify(
			{"checks":checks, "passed":checks.size()-failed.size(), "failed":failed.size()}, "\t"))
	print("STORY_PLAYER_TEST passed=", checks.size()-failed.size(), " failed=", failed.size())
	quit(0 if failed.is_empty() else 1)
