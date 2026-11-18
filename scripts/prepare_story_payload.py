"""Preserve native model inputs in a ZIP; do not interpret story/media content."""
import argparse
import hashlib
import json
import zipfile
from pathlib import Path
from prepare_native_payload import verify


def prepare(root, output):
    assets = root / "assets"
    selected = set()
    suffixes = {".png", ".atlas", ".json", ".spjson", ".spine-json", ".skel"}
    for atlas in assets.rglob("*.atlas"):
        selected.update(p for p in atlas.parent.iterdir()
                        if p.is_file() and p.suffix.lower() in suffixes)
    models = list(assets.rglob("*.model3.json"))
    for model in models:
        selected.add(model)
        refs = json.loads(model.read_text(encoding="utf-8"))["FileReferences"]
        names = [refs["Moc"], *refs["Textures"]]
        names += [refs[k] for k in ("Physics", "Pose", "UserData") if refs.get(k)]
        names += [row["File"] for row in refs.get("Expressions", [])]
        names += [row["File"] for rows in refs.get("Motions", {}).values() for row in rows]
        for name in names:
            path = (model.parent / name).resolve()
            if not path.is_relative_to(root.resolve()) or not path.is_file():
                raise ValueError("Missing or invalid model dependency")
            selected.add(path)
    if not models or not selected:
        raise ValueError("No native model inputs found")
    output.mkdir(parents=True, exist_ok=True)
    target = output / "native_payload.zip"
    if target.exists():
        raise FileExistsError("Preserve existing payload")
    members = {}
    with zipfile.ZipFile(target, "w", zipfile.ZIP_DEFLATED, compresslevel=1) as archive:
        for path in sorted(selected):
            name = path.relative_to(root).as_posix()
            data = path.read_bytes()
            members[name] = {"bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()}
            archive.writestr(name, data)
    digest = hashlib.file_digest(target.open("rb"), "sha256").hexdigest()
    manifest = {"files": members, "required_paths": sorted(members), "archive_sha256": digest}
    (output / "native_payload_manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False), encoding="utf-8")
    print(json.dumps({"files": len(members), "models": len(models),
                      "archive_bytes": target.stat().st_size}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path.cwd())
    parser.add_argument("--verify-pack", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    if args.verify_pack:
        verify(args.verify_pack)
    else:
        prepare(args.root.resolve(), (args.output or args.root).resolve())
