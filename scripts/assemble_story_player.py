"""Assemble a player from story modules, never from the full game host."""
import argparse
import hashlib
import json
import re
import shutil
from pathlib import Path

SCRIPT_REF = re.compile(r'res://(scripts/[^"\s)]+\.gd)')
DATA = (
    "assets.json", "scenario_full.json", "label_map.json", "sound_map.json",
    "expressions.json", "gallery.json", "original_gallery.json",
    "original_story_geometry.json", "original_story_windows.json",
    "original_story_backlog.json", "original_system_terms.json",
    "story_terms.json", "story_cg.json", "story_voice_envelopes.json",
)
DIRECTORIES = (
    "bg", "sprite", "character", "dicing", "story_cg", "voice", "sound",
    "ending", "fonts", "original_menu", "original_story", "original_system", "original_gallery",
)


def gd_function(source, name):
    lines = source.splitlines(keepends=True)
    first = next(i for i, line in enumerate(lines) if line.startswith(f"func {name}("))
    last = next((i for i in range(first + 1, len(lines))
                 if lines[i].startswith("func ")), len(lines))
    return "".join(lines[first:last])


def build_chapter_contexts(source, destination):
    game = (source / "scripts/game.gd").read_text(encoding="utf-8")
    mapping = re.search(r"var home_backgrounds := (\{[^\n]+\})", game)
    if not mapping:
        raise ValueError("Existing caller background mapping not found")
    backgrounds = json.loads(mapping.group(1))
    files = ("scripts/game.gd", "data/chat_events.json", "data/gift_feedback.json")
    source_hashes = {
        name: hashlib.sha256((source / name).read_bytes()).hexdigest() for name in files
    }
    chats = json.loads((source / files[1]).read_text(encoding="utf-8"))["events"]
    responses = json.loads((source / files[2]).read_text(encoding="utf-8"))["responses"]
    entries = [(entry["label"], entry["actor"]) for entry in chats
               if entry.get("kind") == "chat"]
    entries.extend((dialog["label"], entry["actor"])
                   for entry in responses for dialog in entry.get("dialogs", []))
    labels = json.loads((source / "data/scenario_full.json").read_text(
        encoding="utf-8"))["labels"]
    contexts = {}
    for label, actor in entries:
        label = label.removeprefix("*")
        if "*" + label not in labels:
            raise ValueError("Caller references unknown chapter")
        background = backgrounds.get(actor)
        if not background:
            raise ValueError("Caller actor lacks known background")
        previous = contexts.get(label)
        if previous and previous["background"] != background:
            raise ValueError("Conflicting chapter background context")
        contexts[label] = {"background": background, "actor": actor}
    result = {"source_sha256": source_hashes, "chapters": contexts,
              "policy": "existing chat/gift caller mapping; no inferred backgrounds"}
    (destination / "data/chapter_contexts.json").write_text(
        json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    return len(contexts)


def assemble(source, destination, code, windows_runtime=None):
    if destination.exists():
        raise FileExistsError("Use a new output directory; preserve existing projects")
    destination.mkdir(parents=True)
    copied = {}

    def copy(relative):
        path = source / relative
        if not path.is_file():
            raise FileNotFoundError(relative)
        target = destination / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, target)
        copied[relative] = hashlib.sha256(path.read_bytes()).hexdigest()

    for directory in DIRECTORIES:
        for path in sorted((source / "assets" / directory).rglob("*")):
            if path.is_file() and path.suffix != ".import":
                copy(path.relative_to(source).as_posix())
    # Models and their resources are named by the existing story adapter.
    for model in sorted((source / "assets").glob("*.model3.json")):
        copy(model.relative_to(source).as_posix())
        refs = json.loads(model.read_text(encoding="utf-8"))["FileReferences"]
        names = [refs["Moc"], *refs["Textures"]]
        names += [refs[key] for key in ("Physics", "Pose", "UserData") if refs.get(key)]
        names += [entry["File"] for entry in refs.get("Expressions", [])]
        names += [entry["File"] for rows in refs.get("Motions", {}).values() for entry in rows]
        for name in names:
            path = (model.parent / name).resolve()
            if not path.is_relative_to(source) or not path.is_file():
                raise ValueError("Invalid model input")
            copy(path.relative_to(source).as_posix())
        folders = {Path(name).parts[0] for name in names if len(Path(name).parts) > 1}
        for folder in folders:
            for path in sorted((model.parent / folder).rglob("*")):
                if path.is_file() and path.suffix != ".import":
                    copy(path.relative_to(source).as_posix())
    copy("assets/original_home/sprite_1576.png")
    for name in DATA:
        copy("data/" + name)
    context_count = build_chapter_contexts(source, destination)
    for path in (source / "shaders").glob("*"):
        if path.is_file() and path.suffix == ".gdshader":
            copy(path.relative_to(source).as_posix())
    # Keep the proven iOS extension descriptors; build scripts supply native binaries.
    copy("cubism.gdextension")
    descriptor = destination / "cubism.gdextension"
    descriptor.write_text(descriptor.read_text(encoding="utf-8") +
        '\nwindows.editor.x86_64 = "addons/gd_cubism/bin/libgd_cubism.windows.release.x86_64.dll"\n'
        'windows.debug.x86_64 = "addons/gd_cubism/bin/libgd_cubism.windows.release.x86_64.dll"\n',
        encoding="utf-8")
    for path in (source / "addons").rglob("*"):
        if path.is_file() and (path.suffix == ".gdextension"
                               or path.is_relative_to(source / "addons/gd_cubism/res")) \
                and path.suffix not in {".import", ".uid"}:
            copy(path.relative_to(source).as_posix())
    copy("export_presets.cfg")
    config = (source / "project.godot").read_text(encoding="utf-8")
    config = config.replace('config/name="VLoverStory"', 'config/name="V-Lover Story Player"')
    config = config.replace('config/custom_user_dir_name="V-Lover Story Only"',
                            'config/custom_user_dir_name="V-Lover Story Player"')
    config = config.replace('run/main_scene="res://scenes/story_only_ios.tscn"',
                            'run/main_scene="res://scenes/story_player.tscn"')
    (destination / "project.godot").write_text(config, encoding="utf-8")
    (destination / "scenes").mkdir()
    (destination / "scenes/story_player.tscn").write_text(
        '[gd_scene load_steps=2 format=3]\n'
        '[ext_resource type="Script" path="res://scripts/story_player_host.gd" id="1"]\n'
        '[node name="StoryPlayer" type="Control"]\nlayout_mode=3\nanchors_preset=15\n'
        'anchor_right=1.0\nanchor_bottom=1.0\ngrow_horizontal=2\ngrow_vertical=2\n'
        'script=ExtResource("1")\n', encoding="utf-8")
    (destination / "scripts").mkdir()
    host = (code / "story_player/story_player_host.gd").read_text(encoding="utf-8")
    game = (source / "scripts/game.gd").read_text(encoding="utf-8")
    # Mechanical extraction of existing settings UI; no game inheritance.
    host += "\n" + gd_function(game, "_show_settings")
    host += "\n" + gd_function(game, "_apply_settings")
    (destination / "scripts/story_player_host.gd").write_text(host, encoding="utf-8")
    pending = list(SCRIPT_REF.findall(host))
    visited = {"scripts/story_player_host.gd"}
    while pending:
        relative = pending.pop()
        if relative in visited:
            continue
        if Path(relative).name in {"game.gd", "schedule_flow.gd", "phone.gd", "interaction_view.gd"}:
            raise ValueError("Full game module reached: " + relative)
        copy(relative)
        text = (destination / relative).read_text(encoding="utf-8")
        if relative == "scripts/story.gd":
            original = gd_function(text, "_check_achievement")
            text = text.replace(original,
                'func _check_achievement(command: Dictionary) -> void:\n'
                '\t_record("story_only_side_effect_skipped", {"feature":"checkachievement"})\n\n', 1)
            # Imported PNGs have no raw file in the PCK; use the texture loader.
            text = text.replace(
                'var ending_image := Image.load_from_file("res://assets/ending/"+str(arguments[1])+".png")\n'
                '\tbackground.texture = ImageTexture.create_from_image(ending_image)',
                'background.texture = load("res://assets/ending/"+str(arguments[1])+".png") as Texture2D')
            (destination / relative).write_text(text, encoding="utf-8")
        visited.add(relative)
        pending.extend(SCRIPT_REF.findall(text))
    audit = {
        "architecture": "standalone story host; no game or schedule host",
        "source": str(source), "source_sha256": copied,
        "scripts": sorted(visited), "chapters": len(json.loads(
            (destination / "data/scenario_full.json").read_text(encoding="utf-8"))["labels"]),
        "chapters_with_existing_caller_context": context_count,
        "files": sum(p.is_file() for p in destination.rglob("*")),
        "bytes": sum(p.stat().st_size for p in destination.rglob("*") if p.is_file()),
        "limitations": [
            "Existing interpreter effects with compatibility fallbacks remain fallbacks.",
            "Direct chapter entry uses interpreter defaults, not an invented management save.",
            "Physics phase and original Unity timing equivalence are not established.",
        ],
    }
    (destination / "story_player_assembly.json").write_text(
        json.dumps(audit, ensure_ascii=False, indent=2), encoding="utf-8")
    for path in (code / "scripts").iterdir():
        if path.is_file() and path.suffix in {".py", ".sh"}:
            shutil.copy2(path, destination / "scripts" / path.name)
    shutil.copy2(code / "scripts/check_native_extensions.gd",
                 destination / "scripts/check_native_extensions.gd")
    shutil.copy2(code / "story_player/test_player.gd",
                 destination / "scripts/test_player.gd")
    if windows_runtime:
        for name in (
            "spine_godot_extension.gdextension",
            "windows/libspine_godot.windows.atlas-fixed.x86_64.dll",
            "addons/gd_cubism/bin/libgd_cubism.windows.release.x86_64.dll",
        ):
            target = destination / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(windows_runtime / name, target)
    print(json.dumps({k: audit[k] for k in ("architecture", "chapters", "files", "bytes")}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--destination", type=Path, required=True)
    parser.add_argument("--code", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--windows-runtime", type=Path)
    args = parser.parse_args()
    assemble(args.source.resolve(), args.destination.resolve(), args.code.resolve(),
             args.windows_runtime.resolve() if args.windows_runtime else None)
