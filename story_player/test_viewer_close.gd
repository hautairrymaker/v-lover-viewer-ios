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
	await process_frame
	var host: Control = viewer.story_host
	host._open_chapter(0)
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < 15000:
		if host.story_root.message_active: break
		await process_frame
	var reading: bool = is_instance_valid(host.story_root) and host.story_root.message_active
	await host._on_window_close_requested()
	var saved := FileAccess.file_exists(host.AUTO_SAVE)
	var released: bool = host.story_root == null
	print("VIEWER_CLOSE_TEST ", JSON.stringify({
		"reading":reading, "progress_saved":saved, "player_closed":released}))
	viewer.ui.free()
	viewer.voice_player.free()
	viewer.free()
	quit(0 if reading and saved and released else 1)
