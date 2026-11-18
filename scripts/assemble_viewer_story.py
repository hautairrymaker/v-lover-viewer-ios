"""Merge existing viewer and story modules; reject differing shared assets."""
import argparse
import hashlib
import json
import shutil
from pathlib import Path


def sha(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def assemble(viewer, story, code, destination):
    if destination.exists():
        raise FileExistsError("Use a new destination; existing projects are preserved")
    shutil.copytree(viewer, destination, ignore=shutil.ignore_patterns(
        ".git", ".godot", "build", "__pycache__", "*.pyc", "*.import",
        "native_payload.zip", "native_payload_manifest.json"))
    copied = 0
    shared = 0
    # Keep viewer configuration/native descriptors and merge story data only.
    for folder in ("assets", "data", "scripts", "shaders", "addons/gd_cubism/res"):
        for source in sorted((story / folder).rglob("*")):
            if not source.is_file() or source.suffix in {".uid", ".import", ".py", ".sh"}:
                continue
            relative = source.relative_to(story)
            target = destination / relative
            if target.exists():
                if sha(source) != sha(target):
                    if source.suffix not in {".gd", ".gdshader"} or (
                            source.read_text(encoding="utf-8")
                            != target.read_text(encoding="utf-8")):
                        raise ValueError("Conflicting shared input: " + relative.as_posix())
                shared += 1
                continue
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
            copied += 1
    for source in (code / "scripts").glob("*"):
        if source.is_file() and source.suffix in {".py", ".sh"}:
            shutil.copy2(source, destination / "scripts" / source.name)
    shutil.copy2(code / "story_player/viewer_story_mode.gd",
                 destination / "scripts/viewer_story_mode.gd")
    shutil.copy2(code / "story_player/test_viewer_story.gd",
                 destination / "scripts/test_viewer_story.gd")
    shutil.copy2(code / "story_player/capture_viewer_story.gd",
                 destination / "scripts/capture_viewer_story.gd")
    main = (destination / "main.gd").read_text(encoding="utf-8")
    if "var story_host" in main:
        raise ValueError("Expected an unmodified viewer16 main")
    main = main.replace("var native_error: Label", """var native_error: Label
var story_host: Control
var story_container: SubViewportContainer
var viewer_sidebar: Control
var toolbar_controls: Array[Control] = []
var selection_busy := false""", 1)
    main = main.replace('mode.add_item("剧情 CG")',
                        'mode.add_item("剧情 CG")\n\tmode.add_item("剧情")', 1)
    main = main.replace("var sidebar := VBoxContainer.new()",
                        "var sidebar := VBoxContainer.new()\n\tviewer_sidebar = sidebar", 1)
    main = main.replace("mode.item_selected.connect", """for control in toolbar.get_children():
		if control != mode and control is Control: toolbar_controls.append(control)
	mode.item_selected.connect""", 1)
    main = main.replace("func _load_selection() -> void:\n\trebuilding = true",
                        """func _load_selection() -> void:
	if selection_busy: return
	selection_busy = true
	mode.disabled = true
	if is_instance_valid(story_host):
		await story_host.deactivate()
		story_host = null
		story_container.free()
		story_container = null
	var reading := mode.selected == 4
	stage.visible = not reading
	viewer_sidebar.visible = not reading
	for control in toolbar_controls: control.visible = not reading
	_load_viewer_selection(reading)
	selection_busy = false
	mode.disabled = false

func _load_viewer_selection(reading: bool) -> void:
	rebuilding = true""", 1)
    main = main.replace("\tanimation.clear()\n\texpression.clear()",
                        """\tanimation.clear()
	expression.clear()
	if reading:
		_open_story()
		rebuilding = false
		return""", 1)
    main += """

func _open_story() -> void:
	story_container = SubViewportContainer.new()
	story_container.name = "StoryViewport"
	story_container.position = Vector2(16, 64)
	story_container.size = Vector2(1280, 720)
	story_container.scale = Vector2.ONE * minf(1288.0 / 1280.0, 720.0 / 720.0)
	ui.add_child(story_container)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.handle_input_locally = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	story_container.add_child(viewport)
	story_host = preload("res://scripts/viewer_story_mode.gd").new()
	story_host.theme = ui.theme
	viewport.add_child(story_host)
	story_host.leave_requested.connect(func():
		mode.select(2)
		_load_selection())
"""
    (destination / "main.gd").write_text(main, encoding="utf-8")
    descriptor = destination / "cubism.gdextension"
    descriptor.write_text(descriptor.read_text(encoding="utf-8") +
        '\nwindows.editor.x86_64 = "addons/gd_cubism/bin/libgd_cubism.windows.release.x86_64.dll"\n'
        'windows.debug.x86_64 = "addons/gd_cubism/bin/libgd_cubism.windows.release.x86_64.dll"\n',
        encoding="utf-8")
    preset = destination / "export_presets.cfg"
    text = preset.read_text(encoding="utf-8").replace("scripts/*, ", "")
    text = text.replace('include_filter="', 'include_filter="*.txt, *.csv, ', 1)
    preset.write_text(text, encoding="utf-8")
    report = {"viewer_base": "974913476d5dd5144a36c0e2731592a8da02c34a",
              "story_files_added": copied, "equivalent_shared_files": shared,
              "architecture": "viewer fifth mode; original public chapters plus intro",
              "source_manifest_sha256": sha(story / "story_player_assembly.json")}
    (destination / "viewer_story_assembly.json").write_text(
        json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps(report))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    for name in ("viewer", "story", "code", "destination"):
        parser.add_argument("--" + name, required=True, type=Path)
    args = parser.parse_args()
    assemble(args.viewer.resolve(), args.story.resolve(), args.code.resolve(),
             args.destination.resolve())
