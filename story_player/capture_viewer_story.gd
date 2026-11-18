extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var viewer: Node = load("res://main.gd").new()
	root.add_child(viewer)
	await process_frame
	await process_frame
	viewer.mode.select(4)
	await viewer._load_selection()
	for index in 5: await process_frame
	await RenderingServer.frame_post_draw
	var folder := OS.get_environment("VIEWER_STORY_CAPTURE")
	var result := root.get_texture().get_image().save_png(folder.path_join("chapters.png"))
	if result != OK: quit(1); return
	viewer.story_host._open_chapter(0)
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < 15000:
		if viewer.story_host.story_root.message_active: break
		await process_frame
	await create_timer(0.75).timeout
	await RenderingServer.frame_post_draw
	result = root.get_texture().get_image().save_png(folder.path_join("intro.png"))
	await viewer.story_host.deactivate()
	viewer.mode.select(2)
	await viewer._load_selection()
	await process_frame
	viewer.ui.free()
	viewer.voice_player.free()
	viewer.free()
	quit(0 if result == OK else 1)
