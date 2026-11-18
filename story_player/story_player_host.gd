extends Control

const PLAYER = preload("res://scripts/story.gd")
const MENU = preload("res://scripts/original_main_menu.gd")
const GALLERY = preload("res://scripts/story_only_gallery.gd")
const SLOTS = preload("res://scripts/original_save_slots.gd")
const AUDIO = preload("res://scripts/audio_settings.gd")
const AUTO_SAVE := "user://story_auto_save.json"

var phone_root: Control
var story_root: Control
var reading_cards: Array = []
var scenario: Dictionary = {}
var chapter_contexts: Dictionary = {}
var navigation_busy := false
var shutting_down := false
var autosave_elapsed := 0.0
var catalog_error := ""

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_tree().auto_accept_quit = false
	scenario = JSON.parse_string(FileAccess.get_file_as_string("res://data/scenario_full.json"))
	chapter_contexts = JSON.parse_string(FileAccess.get_file_as_string(
		"res://data/chapter_contexts.json")).chapters
	var original: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/gallery.json"))
	var known: Array = []
	for entry in original.cards:
		var label := str(entry.label).trim_prefix("*")
		if not scenario.labels.has("*" + label) or label in known: continue
		var card: Dictionary = entry.duplicate(true)
		card.label = label
		card.enabled = true
		card.playable = true
		reading_cards.append(card)
		known.append(label)
	for source_label in scenario.labels:
		var label := str(source_label).trim_prefix("*")
		if label in known: continue
		reading_cards.append({"id":"reading/" + label, "label":label,
			"title":label, "enabled":true, "playable":true})
		known.append(label)
	var settings := ConfigFile.new()
	settings.load("user://settings.cfg")
	_apply_settings(settings)
	phone_root = Control.new()
	phone_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(phone_root)
	_show_main_menu()

func _show_main_menu() -> void:
	if phone_root.has_node("MainMenu"): return
	var menu := MENU.new()
	menu.name = "MainMenu"
	menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	phone_root.add_child(menu)
	menu.action_requested.connect(_on_main_menu_action.bind(menu))
	for button in menu.actions.get_children():
		if button is BaseButton:
			if button.name == "MainInteraction": button.hide()
			if button.name == "MainNewGame": button.get_node("Caption").text = "从头阅读"
			if button.name == "MainLoad": button.get_node("Caption").text = "读取进度"
			if button.name == "MainSettings":
				button.get_node("Caption").text = "播放设置"
				button.position.y -= 115
	var music := AudioStreamPlayer.new()
	music.name = "MenuMusic"
	music.bus = "BGM"
	music.stream = load("res://assets/sound/長版_MMA.ogg") as AudioStream
	if music.stream is AudioStreamOggVorbis: music.stream.loop = true
	menu.add_child(music)
	music.play()
	menu.tree_exiting.connect(func(): music.stop(); music.stream = null)

func _on_main_menu_action(action: String, menu: Control) -> void:
	match action:
		"MainNewGame": _play_label("開場劇情")
		"MainGallery": _show_gallery(menu)
		"MainLoad": _show_load_slots(menu)
		"MainSettings": _show_settings(menu)
		"MainExit": _shutdown()

func _show_gallery(parent: Control) -> void:
	if parent.has_node("Gallery"): return
	var view := GALLERY.new()
	view.name = "Gallery"
	view.catalog = reading_cards
	view.unlocked = reading_cards.map(func(card): return card.id)
	view.replay_available = true
	view.selected.connect(func(identity: String):
		var found := reading_cards.filter(func(card): return card.id == identity)
		if found.is_empty(): return
		if is_instance_valid(story_root):
			await _return_to_menu()
		_play_label(str(found[0].label)))
	view.closed.connect(view.queue_free)
	parent.add_child(view)

func _new_player() -> Control:
	var player := PLAYER.new()
	player.auto_boot = false
	player.embedded = true
	player.gallery_replay = true
	player.story_done.connect(_return_to_menu)
	player.story_cancelled.connect(_return_to_menu)
	player.request_menu_action.connect(_on_story_menu_action)
	player.request_slot_load.connect(_load_save_path)
	player.request_load.connect(_load_save_path.bind("user://story_quick_save.json"))
	add_child(player)
	player.ops = scenario.ops
	player.labels = scenario.labels
	player._load_catalogs()
	player.option_menu.buttons.guide.disabled = true
	return player

func _play_label(label: String) -> void:
	if navigation_busy or is_instance_valid(story_root): return
	if not scenario.labels.has("*" + label):
		_show_error("Unknown chapter: " + label)
		return
	story_root = _new_player()
	story_root.start_label = label
	story_root.initial_background = str(chapter_contexts.get(label, {}).get("background", ""))
	_set_reading(true)
	autosave_elapsed = 0.0
	story_root._boot()

func _set_reading(reading: bool) -> void:
	phone_root.visible = not reading
	var music := phone_root.get_node_or_null("MainMenu/MenuMusic") as AudioStreamPlayer
	if music != null: music.stream_paused = reading

func _process(delta: float) -> void:
	if not is_instance_valid(story_root) or navigation_busy: return
	autosave_elapsed += delta
	if autosave_elapsed >= 15.0:
		autosave_elapsed = 0.0
		_save_reading()

func _save_reading() -> bool:
	if not is_instance_valid(story_root) or story_root.exiting: return false
	if not story_root.save_to_file(AUTO_SAVE):
		story_root.save_status.text = story_root.save_error
		return false
	return true

func _return_to_menu() -> void:
	if navigation_busy: return
	navigation_busy = true
	if is_instance_valid(story_root):
		var old := story_root
		if not old.exiting: _save_reading()
		await old.close_scene()
		story_root = null
		old.queue_free()
	_set_reading(false)
	navigation_busy = false

func _on_story_menu_action(action: String) -> void:
	if not is_instance_valid(story_root): return
	match action:
		"title": await _return_to_menu()
		"gallery": _show_gallery(story_root.option_menu)
		"settings": _show_settings(story_root.option_menu)
		"exit": _shutdown()

func _show_load_slots(parent: Control) -> void:
	if parent.has_node("SaveSlots"): return
	var view := SLOTS.new()
	view.name = "SaveSlots"
	view.save_mode = false
	view.load_requested.connect(_load_save_path)
	view.closed.connect(view.queue_free)
	parent.add_child(view)

func _load_save_path(path: String) -> void:
	if navigation_busy: return
	if not FileAccess.file_exists(path):
		_show_error("No reading progress in this slot.")
		return
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK or not parser.data is Dictionary:
		_show_error("Invalid reading progress; current chapter was preserved.")
		return
	navigation_busy = true
	var candidate := _new_player()
	candidate.hide()
	var error: String = candidate.validate_state(parser.data)
	if error != "" or not await candidate.load_state(parser.data):
		if error == "": error = candidate.save_error
		await candidate.close_scene()
		candidate.queue_free()
		navigation_busy = false
		_show_error(error)
		return
	if is_instance_valid(story_root):
		await story_root.close_scene()
		story_root.queue_free()
	story_root = candidate
	candidate.gallery_replay = true
	candidate.option_menu.set_open(false)
	candidate.presentation_paused = false
	candidate.show()
	_set_reading(true)
	navigation_busy = false
	autosave_elapsed = 0.0
	candidate.play_restored()

func _show_error(message: String) -> void:
	catalog_error = message
	if is_instance_valid(story_root):
		story_root.save_status.text = message
	else:
		var dialog := AcceptDialog.new()
		dialog.dialog_text = message
		dialog.confirmed.connect(dialog.queue_free)
		dialog.canceled.connect(dialog.queue_free)
		add_child(dialog)
		dialog.popup_centered()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED: _save_reading()
	if what == NOTIFICATION_WM_CLOSE_REQUEST: _on_window_close_requested.call_deferred()

func _on_window_close_requested() -> void:
	await _shutdown()

func _shutdown() -> void:
	if shutting_down: return
	shutting_down = true
	if navigation_busy:
		shutting_down = false
		return
	await _return_to_menu()
	get_tree().quit()
