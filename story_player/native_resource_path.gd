extends RefCounted
## Native readers need physical inputs on iOS, not virtual paths inside the PCK.
static var mirrored: Dictionary = {}
static var payload = preload("res://scripts/native_payload.gd").new()
static var payload_ready := false

static func native_path(path: String) -> String:
	# Godot feature tags are lowercase; get_name() returning "iOS" is unrelated.
	if not OS.has_feature("ios") or not path.begins_with("res://"):
		return ProjectSettings.globalize_path(path)
	if not payload_ready:
		if not payload.prepare():
			push_error(payload.error)
			return ""
		payload_ready = true
	var preserved: String = payload.resolve(path)
	if FileAccess.file_exists(preserved):
		return ProjectSettings.globalize_path(preserved)
	var parent := path.get_base_dir()
	var destination := "user://native_story/" + parent.trim_prefix("res://")
	if not mirrored.has(parent):
		if not _mirror(parent, destination): return ""
		mirrored[parent] = true
	var resolved := destination.path_join(path.get_file())
	if not FileAccess.file_exists(resolved):
		push_error("Native story input missing: " + path)
		return ""
	return ProjectSettings.globalize_path(resolved)

static func _mirror(source: String, destination: String) -> bool:
	if DirAccess.make_dir_recursive_absolute(destination) != OK: return false
	for directory in DirAccess.get_directories_at(source):
		if not _mirror(source.path_join(directory), destination.path_join(directory)): return false
	for entry in DirAccess.get_files_at(source):
		if entry.ends_with(".import") or entry.ends_with(".uid"): continue
		var filename := entry.trim_suffix(".remap")
		var original := source.path_join(filename)
		var target := destination.path_join(filename)
		if FileAccess.file_exists(original):
			var output := FileAccess.open(target, FileAccess.WRITE)
			if output == null: return false
			output.store_buffer(FileAccess.get_file_as_bytes(original))
			if output.get_error() != OK: return false
		elif filename.get_extension().to_lower() == "png" and ResourceLoader.exists(original):
			var texture := load(original) as Texture2D
			if texture == null or texture.get_image().save_png(target) != OK: return false
		else:
			push_error("Native story input missing: " + original)
			return false
	return true
