extends SceneTree

func _initialize() -> void:
	var missing: Array = []
	for identity in ["GDCubismUserModel", "SpineSprite", "SpineAtlasResource", "SpineSkeletonFileResource", "SpineSkeletonDataResource"]:
		if not ClassDB.class_exists(identity): missing.append(identity)
	if not missing.is_empty():
		printerr("Required native classes missing: ", missing)
		quit(1)
		return
	print("Required Live2D and Spine native classes registered.")
	quit(0)
