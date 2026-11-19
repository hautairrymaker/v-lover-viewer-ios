"""Build a minimal exported-PCK test of the story native resource adapter."""
import argparse
import hashlib
import json
import shutil
import zipfile
from pathlib import Path

PROBE = '''extends SceneTree

func _initialize() -> void:
    run.call_deferred()

func run() -> void:
    var adapter = load("res://scripts/native_resource_path.gd")
    var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://fixture.json"))
    var resolved: String = adapter.native_path(fixture.atlas)
    var page: String = resolved.get_base_dir().path_join(fixture.page)
    var checks := {
        "lowercase_ios_feature": OS.has_feature("ios"),
        "uppercase_feature_is_false": not OS.has_feature("iOS"),
        "physical_atlas": not resolved.begins_with("res://") and FileAccess.file_exists(resolved),
        "physical_page": not page.begins_with("res://") and FileAccess.file_exists(page),
        "atlas_sha_matches": FileAccess.get_sha256(resolved) == fixture.atlas_sha256,
        "page_sha_matches": FileAccess.file_exists(page) and FileAccess.get_sha256(page) == fixture.page_sha256,
    }
    var passed := 0
    for value in checks.values():
        if value: passed += 1
    var result := {"checks":checks, "passed":passed, "total":checks.size(), "resolved":resolved,
        "scope":"Windows exported PCK with ios feature; physical native paths, not iPhone rendering"}
    var output := OS.get_environment("STORY_PATH_RESULT")
    if output != "": FileAccess.open(output, FileAccess.WRITE).store_string(JSON.stringify(result, "\\t"))
    print("STORY_PATH_PROBE ", JSON.stringify(result))
    quit(0 if passed == checks.size() else 1)
'''


def create(source, destination):
    destination.mkdir(parents=True, exist_ok=False)
    scripts = destination / "scripts"
    scripts.mkdir()
    for name in ("native_resource_path.gd", "native_payload.gd"):
        shutil.copy2(source / "scripts" / name, scripts / name)
    catalog = json.loads((source / "data/story_cg.json").read_text(encoding="utf-8"))
    target = next(row for row in catalog.values()
                  if len([line for line in (source / row["atlas"][6:]).read_text(
                      encoding="utf-8").splitlines() if line.strip().endswith(".png")]) == 2)
    atlas = source / target["atlas"][6:]
    page = next(line.strip() for line in atlas.read_text(
        encoding="utf-8").splitlines() if line.strip().endswith(".png"))
    members = [atlas, source / target["skeleton"][6:], atlas.parent / page]
    manifest = {}
    archive_path = destination / "native_payload.zip"
    with zipfile.ZipFile(archive_path, "w", zipfile.ZIP_DEFLATED, compresslevel=1) as archive:
        for member in members:
            data = member.read_bytes()
            relative = member.relative_to(source).as_posix()
            manifest[relative] = {"bytes":len(data), "sha256":hashlib.sha256(data).hexdigest()}
            archive.writestr(relative, data)
    (destination / "native_payload_manifest.json").write_text(json.dumps({
        "archive_sha256":hashlib.file_digest(archive_path.open("rb"), "sha256").hexdigest(),
        "files":manifest}), encoding="utf-8")
    (destination / "fixture.json").write_text(json.dumps({
        "atlas":target["atlas"], "page":page,
        "atlas_sha256":hashlib.sha256(atlas.read_bytes()).hexdigest(),
        "page_sha256":hashlib.sha256((atlas.parent / page).read_bytes()).hexdigest(),
    }), encoding="utf-8")
    (destination / "probe.gd").write_text(PROBE, encoding="utf-8")
    (destination / "project.godot").write_text(
        'config_version=5\n[application]\nconfig/name="Story Native Path Probe"\n'
        'config/use_custom_user_dir=true\nconfig/custom_user_dir_name="Story Native Path Probe"\n'
        '[rendering]\nrenderer/rendering_method="gl_compatibility"\n', encoding="utf-8")
    (destination / "export_presets.cfg").write_text(
        '[preset.0]\nname="Path Probe"\nplatform="Windows Desktop"\nrunnable=false\n'
        'custom_features="ios"\nexport_filter="all_resources"\n'
        'include_filter="*.json, *.zip"\nexclude_filter="*.pck"\n'
        'script_export_mode=0\n[preset.0.options]\nbinary_format/embed_pck=false\n',
        encoding="utf-8")
    print(json.dumps({"fixture":str(destination), "members":len(manifest),
        "adapter_sha256":hashlib.sha256((scripts / "native_resource_path.gd").read_bytes()).hexdigest()}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--destination", type=Path, required=True)
    args = parser.parse_args()
    create(args.source.resolve(), args.destination.resolve())
