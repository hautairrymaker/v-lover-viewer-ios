extends Node
## SceneTree 版 viewer.gd 的主场景适配版本。
## 桌面仍可用 `godot --path viewer --script res://viewer.gd -- --cg`；
## 这个文件是给 iOS 用的主场景入口，逻辑与 viewer.gd 等价，另加了三处移动端修正：
##   1. 立绘/语音改走 ResourceLoader，不再用 globalize_path（pck 内没有真实路径）
##   2. Spine 资源先镜像到 user:// 再取真实路径（spine-godot 只能读真实文件）
##   3. 双指缩放 + 工具栏缩放按钮，补上滚轮缺失

const ACTORS := ["idol1", "idol3", "idol2"]
const NAMES := ["三人", "井上早苗", "日向純子", "黑沼唯"]

var catalog: Dictionary
var ui: Control
var stage: Control
var world: Node2D
var mode: OptionButton
var actor: OptionButton
var animation: OptionButton
var expression: OptionButton
var cg_group: OptionButton
var cg_catalog: Array = []
var voice_catalog: Array = []
var voice_cues: Array = []
var voice_choice: OptionButton
var voice_controls: HBoxContainer
var voice_player: AudioStreamPlayer
var parameter_scroll: ScrollContainer
var parameters: VBoxContainer
var pause_toggle: CheckButton
var speed: HSlider
var models: Array = []
## 故意用 Node / Object 而不是 SpineSprite：
## 如果 spine_godot 扩展没编出来，脚本仍能解析并跑 Live2D/立绘，只降级 CG 模式。
var spine: Node
var pictures: Array = []
var selected_animation := ""
var dragging := false
var zoom := 1.0
var pan := Vector2.ZERO
var verified := false
var loaded := false
var rebuilding := false
var app_root: Window


func _ready() -> void:
	app_root = get_tree().root
	_build()


func caption(value: String, parent: Node) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_color_override("font_color", Color("263238"))
	parent.add_child(label)
	return label


func choice(items: Array, parent: Node) -> OptionButton:
	var control := OptionButton.new()
	control.custom_minimum_size = Vector2(160, 36)
	for item in items:
		control.add_item(str(item))
	parent.add_child(control)
	return control


func _build() -> void:
	catalog = JSON.parse_string(FileAccess.get_file_as_string("res://catalog.json"))
	if FileAccess.file_exists("res://cg_catalog.json"):
		cg_catalog = JSON.parse_string(FileAccess.get_file_as_string("res://cg_catalog.json")).groups
	if FileAccess.file_exists("res://cg_voices.json"):
		voice_catalog = JSON.parse_string(FileAccess.get_file_as_string("res://cg_voices.json")).cues
	voice_player = AudioStreamPlayer.new()
	app_root.add_child(voice_player)
	ui = Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	app_root.add_child(ui)
	var theme := Theme.new()
	theme.default_font = load("res://assets/fonts/NotoSansTC-Regular.otf")
	theme.default_font_size = 16
	ui.theme = theme
	var background := ColorRect.new()
	background.color = Color("e9edf0")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(background)
	var toolbar := HBoxContainer.new()
	toolbar.position = Vector2(16, 12)
	toolbar.size = Vector2(1288, 40)
	toolbar.add_theme_constant_override("separation", 12)
	ui.add_child(toolbar)
	mode = choice(["Live2D", "Spine", "立绘"], toolbar)
	if not cg_catalog.is_empty():
		mode.add_item("剧情 CG")
	actor = choice(NAMES, toolbar)
	pause_toggle = CheckButton.new()
	pause_toggle.text = "暂停"
	pause_toggle.add_theme_color_override("font_color", Color("263238"))
	toolbar.add_child(pause_toggle)
	caption("速度", toolbar)
	speed = HSlider.new()
	speed.custom_minimum_size = Vector2(180, 36)
	speed.min_value = 0.1
	speed.max_value = 2.0
	speed.step = 0.05
	speed.value = 1.0
	toolbar.add_child(speed)
	# 移动端没有滚轮，补一对缩放按钮
	for entry in [["－", 1.0 / 1.25], ["＋", 1.25]]:
		var zoom_button := Button.new()
		zoom_button.text = str(entry[0])
		zoom_button.custom_minimum_size = Vector2(44, 36)
		var factor := float(entry[1])
		zoom_button.pressed.connect(func():
			zoom = clampf(zoom * factor, 0.2, 4.0)
			_transform())
		toolbar.add_child(zoom_button)
	var reset := Button.new()
	reset.text = "重置"
	reset.custom_minimum_size = Vector2(80, 36)
	reset.pressed.connect(func():
		pan = Vector2.ZERO
		zoom = 1.0
		_transform())
	toolbar.add_child(reset)
	stage = Control.new()
	stage.position = Vector2(16, 64)
	stage.size = Vector2(1016, 720)
	stage.clip_contents = true
	stage.mouse_filter = Control.MOUSE_FILTER_STOP
	ui.add_child(stage)
	var checker := ColorRect.new()
	checker.size = stage.size
	checker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = "shader_type canvas_item; void fragment(){float p=mod(floor(FRAGCOORD.x/20.0)+floor(FRAGCOORD.y/20.0),2.0);COLOR=vec4(vec3(mix(0.91,0.96,p)),1.0);}"
	var material := ShaderMaterial.new()
	material.shader = shader
	checker.material = material
	stage.add_child(checker)
	world = Node2D.new()
	stage.add_child(world)
	stage.gui_input.connect(_stage_input)
	var sidebar := VBoxContainer.new()
	sidebar.position = Vector2(1048, 64)
	sidebar.size = Vector2(256, 720)
	sidebar.add_theme_constant_override("separation", 10)
	ui.add_child(sidebar)
	cg_group = choice([], sidebar)
	cg_group.visible = false
	for entry in cg_catalog:
		cg_group.add_item(str(entry.name))
	cg_group.item_selected.connect(_load_cg_group)
	caption("动作", sidebar)
	animation = choice([], sidebar)
	voice_choice = choice([], sidebar)
	voice_choice.tooltip_text = "Source sheet / row"
	voice_controls = HBoxContainer.new()
	sidebar.add_child(voice_controls)
	var voice_play := Button.new()
	voice_play.text = "播放语音"
	voice_play.pressed.connect(_play_voice)
	voice_controls.add_child(voice_play)
	var voice_stop := Button.new()
	voice_stop.text = "停止语音"
	voice_stop.pressed.connect(func(): voice_player.stop())
	voice_controls.add_child(voice_stop)
	pause_toggle.toggled.connect(func(value): voice_player.stream_paused = value)
	caption("表情", sidebar)
	expression = choice([], sidebar)
	caption("参数", sidebar)
	var scroll := ScrollContainer.new()
	parameter_scroll = scroll
	scroll.custom_minimum_size = Vector2(256, 520)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sidebar.add_child(scroll)
	parameters = VBoxContainer.new()
	parameters.custom_minimum_size.x = 232
	parameters.add_theme_constant_override("separation", 8)
	scroll.add_child(parameters)
	mode.item_selected.connect(func(_index): _load_selection())
	actor.item_selected.connect(func(_index): _load_selection())
	animation.item_selected.connect(_play_animation)
	expression.item_selected.connect(func(index):
		for model in models:
			var name := expression.get_item_text(index)
			if model.get_expressions().has(name):
				model.start_expression(name))
	if (OS.get_cmdline_user_args().has("--cg") or OS.has_feature("mobile")) and not cg_catalog.is_empty():
		mode.select(3)
	_load_selection()
	if OS.get_environment("VL_VOICE_VERIFY") != "":
		_verify_voices.call_deferred()
	elif OS.get_environment("VL_CG_VERIFY") != "":
		_verify_cg.call_deferred()
	elif OS.get_environment("VL_STUDIO_VERIFY") != "":
		_verify.call_deferred()


func _load_selection() -> void:
	rebuilding = true
	voice_player.stop()
	loaded = false
	models.clear()
	pictures.clear()
	spine = null
	for child in world.get_children():
		world.remove_child(child)
		child.free()
	for child in parameters.get_children():
		parameters.remove_child(child)
		child.queue_free()
	animation.clear()
	expression.clear()
	cg_group.visible = mode.selected == 3
	voice_choice.visible = mode.selected == 3
	voice_controls.visible = mode.selected == 3
	parameter_scroll.custom_minimum_size.y = 380 if mode.selected == 3 else 520
	actor.disabled = mode.selected == 3
	var actors: Array = ACTORS if actor.selected == 0 else [ACTORS[actor.selected - 1]]
	if mode.selected == 0:
		for identity in actors:
			var model = ClassDB.instantiate("GDCubismUserModel")
			if model == null:
				continue
			model.assets = str(catalog.live2d[identity].model)
			model.playback_process_mode = ClassDB.class_get_integer_constant("GDCubismUserModel", "MANUAL")
			world.add_child(model)
			var defaults: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(catalog.live2d[identity].defaults))
			for parameter in model.get_parameters():
				parameter.value = defaults.parameters.get(parameter.id, parameter.default_value)
			for part in model.get_part_opacities():
				part.value = defaults.parts.get(part.id, 1.0)
			var info: Dictionary = model.get_canvas_info()
			var factor := minf((stage.size.x / actors.size()) / float(info.size_in_pixels.x), 660.0 / float(info.size_in_pixels.y))
			model.scale = Vector2.ONE * factor
			model.position = Vector2(stage.size.x * (models.size() + 0.5) / actors.size(), stage.size.y * 0.5)
			models.append(model)
		if models.is_empty():
			# 原生扩展没加载起来时不要崩，界面留着并报错
			push_error("Live2D 模型创建失败：GDCubismUserModel 不可用（gd_cubism 扩展未加载）")
			rebuilding = false
			loaded = false
			_transform()
			return
		for name in models[0].get_motions():
			animation.add_item(name)
		for name in models[0].get_expressions():
			expression.add_item(name)
		for parameter in models[0].get_parameters():
			var label := caption(str(parameter.id), parameters)
			label.add_theme_color_override("font_color", Color("263238"))
			var slider := HSlider.new()
			slider.min_value = parameter.minimum_value
			slider.max_value = parameter.maximum_value
			slider.step = 0.001
			slider.value = parameter.value
			slider.value_changed.connect(_set_parameter.bind(str(parameter.id)))
			parameters.add_child(slider)
	elif mode.selected == 1:
		var entries: Array = catalog.spine
		for index in entries.size():
			animation.add_item(str(entries[index].name))
		_load_spine(0)
	elif mode.selected == 2:
		for identity in actors:
			var texture_source := load(str(catalog.portraits[identity])) as Texture2D
			if texture_source == null:
				continue
			var texture := Sprite2D.new()
			texture.texture = texture_source
			var factor := minf((stage.size.x / actors.size() - 16.0) / texture_source.get_width(), 680.0 / texture_source.get_height())
			texture.scale = Vector2.ONE * factor
			texture.position = Vector2(stage.size.x * (pictures.size() + 0.5) / actors.size(), stage.size.y * 0.5)
			world.add_child(texture)
			pictures.append(texture)
	else:
		_load_cg_group(maxi(cg_group.selected, 0))
	animation.disabled = mode.selected == 2
	expression.disabled = mode.selected != 0
	rebuilding = false
	if mode.selected == 0 and animation.item_count > 0:
		_play_animation(0)
	loaded = true
	_transform()


func _set_parameter(value: float, identity: String) -> void:
	if rebuilding:
		return
	for model in models:
		for parameter in model.get_parameters():
			if str(parameter.id) == identity:
				parameter.hold = true
				parameter.value = value


func _play_animation(index: int) -> void:
	if rebuilding:
		return
	if mode.selected == 3:
		_play_cg_clip(index)
		return
	if mode.selected == 1:
		_load_spine(index)
		return
	selected_animation = animation.get_item_text(index)
	for model in models:
		if model.get_motions().has(selected_animation):
			model.start_motion_loop(selected_animation, 0, ClassDB.class_get_integer_constant("GDCubismUserModel", "PRIORITY_FORCE"), true, true)


func _load_spine(index: int) -> void:
	_load_spine_entry(catalog.spine[index])


func _spine_ready() -> bool:
	return ClassDB.class_exists("SpineSprite") and ClassDB.class_exists("SpineAtlasResource")


func _spine_skeleton() -> Object:
	return spine.call("get_skeleton") if spine != null else null


func _spine_state() -> Object:
	return spine.call("get_animation_state") if spine != null else null


func _load_spine_entry(entry: Dictionary) -> void:
	if spine != null:
		world.remove_child(spine)
		spine.free()
		spine = null
	if not _spine_ready():
		push_error("spine_godot 扩展未加载，CG / Spine 模式不可用（Live2D 与立绘不受影响）")
		return
	var paths := _spine_paths(entry)
	var atlas: Object = ClassDB.instantiate("SpineAtlasResource")
	var skeleton: Object = ClassDB.instantiate("SpineSkeletonFileResource")
	if atlas.call("load_from_atlas_file", paths["atlas"]) != OK:
		push_error("Spine atlas 加载失败: %s" % paths["atlas"])
		return
	if skeleton.call("load_from_file", paths["skeleton"]) != OK:
		push_error("Spine skeleton 加载失败: %s" % paths["skeleton"])
		return
	var data: Object = ClassDB.instantiate("SpineSkeletonDataResource")
	data.set("atlas_res", atlas)
	data.set("skeleton_file_res", skeleton)
	if not data.call("is_skeleton_data_loaded"):
		push_error("Spine skeleton data 未加载")
		return
	spine = ClassDB.instantiate("SpineSprite")
	if entry.get("cg", false):
		var multiply := ShaderMaterial.new()
		multiply.shader = load("res://shaders/spine_straight_alpha_multiply.gdshader")
		spine.call("set_multiply_material", multiply)
	spine.call("set_update_mode", 2)
	spine.set("skeleton_data_res", data)
	world.add_child(spine)
	var skel := _spine_skeleton()
	if str(entry.get("skin", "")) != "" and skel != null:
		skel.call("set_skin_by_name", str(entry.skin))
	var state := _spine_state()
	if state != null:
		state.call("set_animation", str(entry.animation), true, 0)
	spine.call("update_skeleton", 0.0)
	var bounds: Rect2 = skel.call("get_bounds") if skel != null else Rect2()
	var factor := minf(940.0 / maxf(bounds.size.x, 1.0), 660.0 / maxf(bounds.size.y, 1.0))
	spine.scale = Vector2.ONE * factor
	spine.position = stage.size * 0.5 - bounds.get_center() * factor


## spine-godot 只能读真实文件路径。桌面直接 globalize_path；
## iOS 上 res:// 在 pck 里没有真实路径，所以先把同目录镜像到 user:// 再取路径。
func _spine_paths(entry: Dictionary) -> Dictionary:
	var atlas_res := str(entry.atlas)
	var skeleton_res := str(entry.skeleton)
	if not OS.has_feature("mobile"):
		return {
			"atlas": ProjectSettings.globalize_path(atlas_res),
			"skeleton": ProjectSettings.globalize_path(skeleton_res),
		}
	var dir_res := atlas_res.get_base_dir()
	var dir_user := "user://spine_cache/%d" % absi(dir_res.hash())
	if not DirAccess.dir_exists_absolute(dir_user):
		_mirror_dir(dir_res, dir_user)
	return {
		"atlas": ProjectSettings.globalize_path(dir_user.path_join(atlas_res.get_file())),
		"skeleton": ProjectSettings.globalize_path(dir_user.path_join(skeleton_res.get_file())),
	}


func _mirror_dir(src: String, dst: String) -> void:
	DirAccess.make_dir_recursive_absolute(dst)
	var dir := DirAccess.open(src)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name.begins_with("."):
			name = dir.get_next()
			continue
		var from_path := src.path_join(name)
		var to_path := dst.path_join(name)
		if dir.current_is_dir():
			_mirror_dir(from_path, to_path)
		else:
			var bytes := FileAccess.get_file_as_bytes(from_path)
			if not bytes.is_empty():
				var out := FileAccess.open(to_path, FileAccess.WRITE)
				if out != null:
					out.store_buffer(bytes)
					out.close()
		name = dir.get_next()
	dir.list_dir_end()


func _load_cg_group(index: int) -> void:
	if index < 0 or index >= cg_catalog.size():
		return
	voice_player.stop()
	var entry: Dictionary = cg_catalog[index]
	animation.clear()
	for clip in entry.animations:
		animation.add_item(str(clip.name))
	_load_spine_entry(entry)
	_refresh_voices()
	loaded = spine != null
	pan = Vector2.ZERO
	zoom = 1.0
	_transform()


func _play_cg_clip(index: int) -> void:
	if spine == null or index < 0:
		return
	voice_player.stop()
	var clip: Dictionary = cg_catalog[cg_group.selected].animations[index]
	var state := _spine_state()
	var skel := _spine_skeleton()
	if state == null or skel == null:
		return
	state.call("clear_tracks")
	skel.call("set_to_setup_pose")
	state.call("set_animation", str(clip.name), true, 0)
	spine.call("update_skeleton", 0.0)
	_refresh_voices()


func _refresh_voices() -> void:
	voice_choice.clear()
	voice_cues.clear()
	if mode.selected != 3 or animation.selected < 0:
		return
	var group_name := str(cg_catalog[cg_group.selected].name)
	var clip_name := animation.get_item_text(animation.selected)
	for cue in voice_catalog:
		if cue.group == group_name and cue.animation == clip_name:
			voice_cues.append(cue)
			voice_choice.add_item("%s / %s" % [cue.source.sheet, cue.source.row])
	voice_choice.disabled = voice_cues.is_empty()
	for button in voice_controls.get_children():
		button.disabled = voice_cues.is_empty()


func _load_voice_stream(path: String) -> AudioStream:
	if ResourceLoader.exists(path):
		return load(path) as AudioStream
	return AudioStreamOggVorbis.load_from_file(ProjectSettings.globalize_path(path))


func _play_voice() -> void:
	if voice_choice.selected < 0 or voice_choice.selected >= voice_cues.size():
		return
	var cue: Dictionary = voice_cues[voice_choice.selected]
	voice_player.stop()
	voice_player.stream = _load_voice_stream(str(cue.path))
	voice_player.pitch_scale = 1.0
	if voice_player.stream != null:
		voice_player.play()
		voice_player.stream_paused = pause_toggle.button_pressed


func _verify_voices() -> void:
	var output := OS.get_environment("VL_VOICE_VERIFY")
	DirAccess.make_dir_recursive_absolute(output)
	var checks: Array = []
	voice_player.volume_db = -80.0
	mode.select(3)
	_load_selection()
	var count := 0
	for group_index in cg_catalog.size():
		cg_group.select(group_index)
		_load_cg_group(group_index)
		for clip_index in animation.item_count:
			animation.select(clip_index)
			_play_cg_clip(clip_index)
			for cue in voice_cues:
				count += 1
				checks.append({"check": "file_exists", "ok": FileAccess.file_exists(cue.path)})
				checks.append({"check": "binding", "ok": cue.group == cg_catalog[group_index].name and cue.animation == animation.get_item_text(clip_index)})
			if not voice_cues.is_empty():
				voice_choice.select(0)
				_play_voice()
				checks.append({"check": "stream_loaded", "ok": voice_player.stream != null and voice_player.stream.get_length() > 0})
				checks.append({"check": "playing", "ok": voice_player.playing})
				pause_toggle.button_pressed = true
				checks.append({"check": "pause", "ok": voice_player.stream_paused})
				pause_toggle.button_pressed = false
				checks.append({"check": "resume", "ok": not voice_player.stream_paused})
				voice_player.stop()
				checks.append({"check": "stop", "ok": not voice_player.playing})
	checks.append({"check": "all_cues_reachable", "ok": count == voice_catalog.size(), "count": count})
	var passed := checks.filter(func(item): return item.ok).size()
	FileAccess.open(output.path_join("result.json"), FileAccess.WRITE).store_string(JSON.stringify({"passed": passed, "total": checks.size(), "checks": checks, "audio_output": "muted; use Dummy driver", "content_reviewed": false}, "\t"))
	get_tree().quit(0 if passed == checks.size() else 1)


func _verify_cg() -> void:
	var output := OS.get_environment("VL_CG_VERIFY")
	DirAccess.make_dir_recursive_absolute(output)
	mode.select(3)
	_load_selection()
	var checks: Array = []
	var clip_count := 0
	for index in cg_catalog.size():
		cg_group.select(index)
		_load_cg_group(index)
		checks.append({"group": index, "check": "loaded", "ok": spine != null})
		if spine == null:
			continue
		var moving := false
		var colored_max := 0
		for clip_index in animation.item_count:
			animation.select(clip_index)
			_play_cg_clip(clip_index)
			clip_count += 1
			if clip_index < 3:
				spine.call("update_skeleton", 0.1)
				await get_tree().process_frame
				await RenderingServer.frame_post_draw
				var before := app_root.get_texture().get_image().get_region(Rect2i(16, 64, 1016, 720))
				var bytes := before.get_data()
				var colored := 0
				for p in range(0, bytes.size(), 4):
					if maxi(bytes[p], maxi(bytes[p + 1], bytes[p + 2])) - mini(bytes[p], mini(bytes[p + 1], bytes[p + 2])) > 30:
						colored += 1
				colored_max = maxi(colored_max, colored)
				spine.call("update_skeleton", 0.31)
				await get_tree().process_frame
				await RenderingServer.frame_post_draw
				var after := app_root.get_texture().get_image().get_region(Rect2i(16, 64, 1016, 720))
				moving = moving or before.get_data() != after.get_data()
				if clip_index == 0:
					after.save_png(output.path_join("cg_%02d.png" % index))
			else:
				spine.call("update_skeleton", 0.1)
		checks.append({"group": index, "check": "colored_pixels", "value": colored_max, "ok": colored_max > 1000})
		checks.append({"group": index, "check": "animated_pixels", "ok": moving})
	pause_toggle.button_pressed = true
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var frozen := app_root.get_texture().get_image().get_data()
	await get_tree().create_timer(0.25).timeout
	await RenderingServer.frame_post_draw
	checks.append({"check": "pause_freezes_pixels", "ok": frozen == app_root.get_texture().get_image().get_data()})
	var passed := checks.filter(func(item): return item.ok).size()
	FileAccess.open(output.path_join("result.json"), FileAccess.WRITE).store_string(JSON.stringify({
		"passed": passed, "total": checks.size(), "groups": cg_catalog.size(), "clips": clip_count,
		"checks": checks, "scope": "Independent CG asset viewer loading and pixel animation; not original scene/voice/Timeline equivalence"}, "\t"))
	get_tree().quit(0 if passed == checks.size() else 1)


func _stage_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			dragging = event.pressed
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			zoom = clampf(zoom * (1.1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.1), 0.2, 4.0)
			_transform()
	if event is InputEventMouseMotion and dragging:
		if not (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
			dragging = false
			return
		pan += event.relative
		_transform()
	if event is InputEventMagnifyGesture:
		zoom = clampf(zoom * event.factor, 0.2, 4.0)
		_transform()
	if event is InputEventPanGesture:
		pan += event.delta
		_transform()


func _transform() -> void:
	world.scale = Vector2.ONE * zoom
	world.position = stage.size * 0.5 * (1.0 - zoom) + pan


func _process(delta: float) -> void:
	if pause_toggle == null or pause_toggle.button_pressed or not loaded:
		return
	var scaled := delta * speed.value
	for model in models:
		model.advance(scaled)
	if spine != null:
		spine.call("update_skeleton", scaled)


func _verify() -> void:
	var output := OS.get_environment("VL_STUDIO_VERIFY")
	DirAccess.make_dir_recursive_absolute(output)
	var checks: Array = []
	for selected_mode in range(3):
		mode.select(selected_mode)
		for selected_actor in range(4):
			actor.select(selected_actor)
			_load_selection()
			await get_tree().create_timer(0.45).timeout
			checks.append({"mode": selected_mode, "actor": selected_actor, "loaded": loaded and (models.size() == (3 if selected_actor == 0 else 1) if selected_mode == 0 else spine != null if selected_mode == 1 else pictures.size() == (3 if selected_actor == 0 else 1))})
			await RenderingServer.frame_post_draw
			var image := app_root.get_texture().get_image()
			image.save_png(output.path_join("mode%d_actor%d.png" % [selected_mode, selected_actor]))
			var pixels := image.get_region(Rect2i(16, 64, 1016, 720)).get_data()
			var colored := 0
			for pixel in range(0, pixels.size(), 4):
				var high := maxi(pixels[pixel], maxi(pixels[pixel + 1], pixels[pixel + 2]))
				var low := mini(pixels[pixel], mini(pixels[pixel + 1], pixels[pixel + 2]))
				if high - low > 30:
					colored += 1
			checks.append({"mode": selected_mode, "actor": selected_actor, "colored_pixels": colored, "loaded": colored > 1000})
	for index in catalog.spine.size():
		mode.select(1)
		if index == 0:
			_load_selection()
		_load_spine(index)
		checks.append({"spine": index, "loaded": spine != null})
	for animated_mode in [0, 1]:
		mode.select(animated_mode)
		actor.select(0)
		_load_selection()
		await get_tree().create_timer(0.3).timeout
		await RenderingServer.frame_post_draw
		var before_pixels := app_root.get_texture().get_image().get_region(Rect2i(16, 64, 1016, 720)).get_data()
		await get_tree().create_timer(0.6).timeout
		await RenderingServer.frame_post_draw
		var after_pixels := app_root.get_texture().get_image().get_region(Rect2i(16, 64, 1016, 720)).get_data()
		checks.append({"animated_mode": animated_mode, "motion_changes_pixels": true, "loaded": before_pixels != after_pixels})
		pause_toggle.button_pressed = true
		await get_tree().create_timer(0.1).timeout
		await RenderingServer.frame_post_draw
		var paused_pixels := app_root.get_texture().get_image().get_region(Rect2i(16, 64, 1016, 720)).get_data()
		await get_tree().create_timer(0.3).timeout
		await RenderingServer.frame_post_draw
		checks.append({"animated_mode": animated_mode, "pause_freezes_pixels": true, "loaded": paused_pixels == app_root.get_texture().get_image().get_region(Rect2i(16, 64, 1016, 720)).get_data()})
		pause_toggle.button_pressed = false
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	_stage_input(wheel)
	checks.append({"wheel_zoom": true, "loaded": is_equal_approx(world.scale.x, 1.1)})
	var before := world.position
	_stage_input(InputEventMouseButton.new())
	dragging = true
	var motion := InputEventMouseMotion.new()
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	motion.relative = Vector2(30, 12)
	_stage_input(motion)
	checks.append({"drag": true, "loaded": world.position != before})
	var passed := checks.filter(func(item): return item.loaded).size()
	FileAccess.open(output.path_join("result.json"), FileAccess.WRITE).store_string(JSON.stringify({"passed": passed, "total": checks.size(), "checks": checks, "scope": "Independent asset viewer loading/rendering/control smoke checks; not original game UI equivalence"}, "\t"))
	get_tree().quit(0 if passed == checks.size() else 1)
