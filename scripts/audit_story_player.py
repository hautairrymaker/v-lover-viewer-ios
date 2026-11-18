"""Check story inputs and classify existing interpreter fallbacks without reading media."""
import argparse
import collections
import hashlib
import json
import re
from pathlib import Path


def audit(root, output):
    def read(name):
        return json.loads((root / "data" / name).read_text(encoding="utf-8"))

    scenario = read("scenario_full.json")
    assets = read("assets.json")
    geometry = read("original_story_geometry.json")
    cg = read("story_cg.json")
    required = set()
    for bank in ("image", "voice"):
        required.update(assets[bank].values())
    required.update(entry["path"] for entry in read("sound_map.json").values()
                    if isinstance(entry, dict) and entry.get("path"))
    for row in geometry["characters"]:
        if row.get("FileType") == "Dicing" and row.get("FileName") and row.get("SubFileName"):
            name = row["SubFileName"].replace("[", "_").replace("]", "_")
            required.add("res://assets/dicing/" + name + ".png")
    for group in cg.values():
        required.update((group["atlas"], group["skeleton"]))
    for card in read("original_gallery.json")["cards"]:
        required.add(card["thumbnail"])
    model_count = 0
    for model in (root / "assets").glob("*.model3.json"):
        model_count += 1
        refs = json.loads(model.read_text(encoding="utf-8"))["FileReferences"]
        names = [refs["Moc"], *refs["Textures"]]
        names += [refs[key] for key in ("Physics", "Pose", "UserData") if refs.get(key)]
        names += [entry["File"] for entry in refs.get("Expressions", [])]
        names += [entry["File"] for rows in refs.get("Motions", {}).values() for entry in rows]
        required.update("res://" + (model.parent / name).relative_to(root).as_posix()
                        for name in names)
    for script in (root / "scripts").glob("*.gd"):
        if script.name.startswith(("test_", "check_")):
            continue
        for path in re.findall(r'res://[^"\n]+\.(?:gdshader|gd|json|png|otf|ogg)(?=")',
                               script.read_text(encoding="utf-8")):
            if any(token in path for token in ("%", '"', "+")):
                continue
            if path == "res://native_payload_manifest.json":
                continue  # Generated before export, verified inside the actual PCK.
            required.add(path)
    missing = sorted(path for path in required
                     if path.startswith("res://") and not (root / path[6:]).is_file())
    missing_targets = []
    for index, op in enumerate(scenario["ops"]):
        if op["op"] in {"jump", "jumpsubroutine", "thread", "waitthread"} and op.get("label"):
            target = "*" + str(op["label"]).strip().removeprefix("*")
            if target not in scenario["labels"]:
                missing_targets.append({"index": index, "op": op["op"], "target": target})
    placeholders = {
        "imageeffect", "imageeffectoff", "pagecontrol", "waitpopup", "tween",
        "eyewipeon", "eyewipeoff", "skipeffect", "addnograyout", "clearnograyout",
    }
    counts = collections.Counter(op["op"] for op in scenario["ops"])
    scripts = sorted(path.name for path in (root / "scripts").glob("*.gd"))
    forbidden = {"game.gd", "phone.gd", "schedule_flow.gd", "interaction_view.gd"}
    source = (root / "scripts/story_player_host.gd").read_text(encoding="utf-8")
    result = {
        "source_sha256": hashlib.sha256((root / "data/scenario_full.json").read_bytes()).hexdigest(),
        "chapter_labels": len(scenario["labels"]), "operations": len(scenario["ops"]),
        "dialogue_lines": counts["say"], "cg_groups": len(cg),
        "model_configs": model_count,
        "required_paths": len(required), "missing_paths": missing,
        "missing_jump_targets": missing_targets, "runtime_scripts": scripts,
        "no_full_game_host": not (set(scripts) & forbidden)
                             and source.startswith("extends Control"),
        "operation_counts": dict(sorted(counts.items())),
        "existing_placeholder_operations": {key: counts[key] for key in sorted(placeholders) if counts[key]},
        "conditional_operations": sum(counts[key] for key in ("if", "elseif", "selection")),
        "coverage_limit": "Static resource and target audit, not natural playback of all branches.",
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({key: result[key] for key in (
        "chapter_labels", "operations", "dialogue_lines", "cg_groups",
        "required_paths", "no_full_game_host")}))
    print(json.dumps({"missing_paths": len(missing), "missing_jump_targets": len(missing_targets),
                      "existing_placeholder_operations": result["existing_placeholder_operations"]}))
    if missing or missing_targets or not result["no_full_game_host"]:
        raise SystemExit(1)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("root", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    audit(args.root.resolve(), args.output.resolve())
