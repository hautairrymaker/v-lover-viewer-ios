extends "res://scripts/story_player_host.gd"

signal leave_requested

var chapter_list: ItemList
var chapter_title: Label
var play_button: Button
var resume_button: Button
var previous_auto_accept_quit := true
var closing_application := false

func _ready() -> void:
	previous_auto_accept_quit = get_tree().auto_accept_quit
	super._ready()

func _exit_tree() -> void:
	get_tree().auto_accept_quit = previous_auto_accept_quit

func _on_window_close_requested() -> void:
	if closing_application: return
	closing_application = true
	await deactivate()
	get_tree().quit()

func _show_main_menu() -> void:
	# Only original public gallery entries are chapter entry points.
	var original: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/gallery.json"))
	reading_cards.clear()
	reading_cards.append({"id":"intro", "label":"開場劇情", "title":"開場劇情"})
	for entry in original.cards:
		if entry.get("playable", false) and scenario.labels.has("*" + str(entry.label).trim_prefix("*")):
			reading_cards.append(entry.duplicate(true))
	var panel := VBoxContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_theme_constant_override("separation", 12)
	phone_root.add_child(panel)
	chapter_title = Label.new()
	chapter_title.text = "剧情"
	chapter_title.add_theme_font_size_override("font_size", 26)
	panel.add_child(chapter_title)
	chapter_list = ItemList.new()
	chapter_list.name = "Chapters"
	chapter_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chapter_list.add_theme_font_size_override("font_size", 22)
	chapter_list.fixed_icon_size = Vector2i(48, 48)
	for card in reading_cards:
		chapter_list.add_item(str(card.title))
	chapter_list.item_activated.connect(_open_chapter)
	panel.add_child(chapter_list)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 14)
	panel.add_child(actions)
	play_button = _button(actions, "播放", func():
		var selected := chapter_list.get_selected_items()
		if not selected.is_empty(): _open_chapter(selected[0]))
	resume_button = _button(actions, "继续阅读", func(): _load_save_path(AUTO_SAVE))
	_button(actions, "读取进度", func(): _show_load_slots(phone_root))
	_button(actions, "播放设置", func(): _show_settings(phone_root))
	chapter_list.select(0)
	_refresh_resume()

func _button(parent: Node, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(160, 52)
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func _open_chapter(index: int) -> void:
	if index >= 0 and index < reading_cards.size():
		_play_label(str(reading_cards[index].label).trim_prefix("*"))

func _refresh_resume() -> void:
	resume_button.disabled = not FileAccess.file_exists(AUTO_SAVE)

func _set_reading(reading: bool) -> void:
	phone_root.visible = not reading
	if not reading and is_instance_valid(resume_button): _refresh_resume()

func _apply_settings(settings: ConfigFile) -> void:
	AUDIO.apply(settings)
	if is_instance_valid(story_root):
		story_root.message_character_seconds = AUDIO.character_interval(settings)

func _on_story_menu_action(action: String) -> void:
	if not is_instance_valid(story_root): return
	match action:
		"title", "gallery": await _return_to_menu()
		"settings": _show_settings(story_root.option_menu)
		"exit": await _shutdown()

func deactivate() -> void:
	if navigation_busy:
		while navigation_busy: await get_tree().process_frame
	await _return_to_menu()

func _shutdown() -> void:
	await deactivate()
	leave_requested.emit()
