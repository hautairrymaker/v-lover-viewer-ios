extends RefCounted

var error := ""
var cache_root := ""

func prepare() -> bool:
	var text := FileAccess.get_file_as_string("res://native_payload_manifest.json")
	var parsed = JSON.parse_string(text)
	if not parsed is Dictionary:
		error = "Native payload manifest missing or invalid"
		return false
	var manifest: Dictionary = parsed
	cache_root = "user://native_payload/" + str(manifest.archive_sha256)
	var complete := cache_root.path_join("complete")
	if FileAccess.file_exists(complete):
		var valid := true
		for name in manifest.files:
			if not FileAccess.file_exists(cache_root.path_join(name)):
				valid = false
				break
		if valid:
			return true
	var archive := ZIPReader.new()
	if archive.open("res://native_payload.zip") != OK:
		error = "Cannot open native payload archive"
		return false
	for name in manifest.files:
		if name.is_absolute_path() or ".." in name.split("/"):
			error = "Invalid native payload path"
			archive.close()
			return false
		var bytes := archive.read_file(name)
		var info: Dictionary = manifest.files[name]
		if bytes.size() != int(info.bytes):
			error = "Native file is missing or truncated: " + name
			archive.close()
			return false
		var hashing := HashingContext.new()
		hashing.start(HashingContext.HASH_SHA256)
		hashing.update(bytes)
		if hashing.finish().hex_encode() != str(info.sha256):
			error = "Native file checksum mismatch: " + name
			archive.close()
			return false
		var destination := cache_root.path_join(name)
		if DirAccess.make_dir_recursive_absolute(destination.get_base_dir()) != OK:
			error = "Cannot create native cache directory"
			archive.close()
			return false
		var file := FileAccess.open(destination, FileAccess.WRITE)
		if file == null:
			error = "Cannot write native cache: " + name
			archive.close()
			return false
		file.store_buffer(bytes)
		file.close()
	archive.close()
	var marker := FileAccess.open(complete, FileAccess.WRITE)
	if marker == null:
		error = "Cannot finish native cache"
		return false
	marker.store_string(str(manifest.archive_sha256))
	marker.close()
	return true

func resolve(path: String) -> String:
	return cache_root.path_join(path.trim_prefix("res://"))
