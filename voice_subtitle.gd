extends PanelContainer

var text_view: RichTextLabel


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.06, 0.07, 0.08, 0.86)
	background.content_margin_left = 12
	background.content_margin_right = 12
	background.content_margin_top = 10
	background.content_margin_bottom = 10
	add_theme_stylebox_override("panel", background)
	text_view = RichTextLabel.new()
	text_view.bbcode_enabled = false
	text_view.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_view.add_theme_color_override("default_color", Color.WHITE)
	text_view.add_theme_font_size_override("normal_font_size", 20)
	text_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(text_view)
	clear_caption()


func show_caption(value: String) -> void:
	text_view.text = value
	text_view.scroll_to_line(0)
	visible = not value.strip_edges().is_empty()


func clear_caption() -> void:
	if text_view != null:
		text_view.text = ""
	hide()
