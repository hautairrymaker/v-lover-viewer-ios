extends SceneTree

var viewer: Node
var results: Array = []
var active: Dictionary = {}

func _initialize() -> void:
	run.call_deferred()

func stage_event(kind: String, detail: Dictionary) -> void:
	if active.is_empty(): return
	if kind == "portrait": active.portrait_seen = true
	if kind == "model_loaded": active.live2d_seen = true
	if kind == "cg_loaded":
		active.cg_seen = true
		active.cg_name = detail.name
		viewer.story_host.story_root.fast = false
		active.live2d_at_cg_load = is_instance_valid(viewer.story_host.story_root.stage.model)
		active.portrait_textures_at_cg_load = 0
		for node in viewer.story_host.story_root.portrait_stage.nodes.values():
			if node.texture != null: active.portrait_textures_at_cg_load += 1

func run() -> void:
	viewer = load("res://main.gd").new()
	root.add_child(viewer)
	await process_frame
	await process_frame
	viewer.mode.select(4)
	await viewer._load_selection()
	var host: Control = viewer.story_host
	var limit := int(OS.get_environment("CG_TRANSITION_LIMIT"))
	if limit <= 0: limit = host.reading_cards.size() - 1
	for index in range(1, mini(limit + 1, host.reading_cards.size())):
		active = {"index":index, "portrait_seen":false, "live2d_seen":false,
			"cg_seen":false, "dialogue_after_cg":false}
		host._open_chapter(index)
		var player: Control = host.story_root
		player.stage.event.connect(stage_event)
		player.cg_stage.event.connect(stage_event)
		player.portrait_stage.event.connect(stage_event)
		var started := Time.get_ticks_msec()
		while Time.get_ticks_msec() - started < 45000 and is_instance_valid(player) and not player.exiting:
			if active.cg_seen and player.message_active:
				active.dialogue_after_cg = true
				player.fast = false
				player.presentation_paused = true
				break
			await process_frame
		active.elapsed_ms = Time.get_ticks_msec() - started
		active.static_bytes = OS.get_static_memory_usage()
		active.ok = active.cg_seen and active.dialogue_after_cg
		if active.cg_seen and is_instance_valid(player):
			var clock: float = player.cg_stage.elapsed
			await create_timer(0.1).timeout
			active.cg_advances = is_instance_valid(player) and player.cg_stage.elapsed > clock
			active.ok = active.ok and active.cg_advances
		results.append(active.duplicate(true))
		print("CG_TRANSITION_CHAPTER ", JSON.stringify(active))
		active = {}
		await host._return_to_menu()
		await process_frame
	viewer.mode.select(2)
	await viewer._load_selection()
	var failed := results.filter(func(row): return not row.ok).size()
	var result := {"chapters":results, "passed":results.size()-failed,
		"total":results.size(), "failed":failed,
		"scope":"Actual viewer interpreter through first CG dialogue; not iPhone crash proof"}
	var output := OS.get_environment("CG_TRANSITION_RESULT")
	if output != "": FileAccess.open(output, FileAccess.WRITE).store_string(JSON.stringify(result, "\t"))
	print("CG_TRANSITION_RESULT ", JSON.stringify(result))
	viewer.ui.free()
	viewer.voice_player.free()
	viewer.free()
	quit(0 if failed == 0 else 1)
