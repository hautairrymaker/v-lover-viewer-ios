"""Keep raw native-loader inputs intact across Godot resource export."""
import argparse
import hashlib
import io
import json
import struct
import zipfile
from pathlib import Path

SUFFIXES = {".json", ".moc3", ".atlas", ".spjson", ".spine-json", ".skel", ".png"}


def required_paths(root):
    catalog = json.loads((root / "catalog.json").read_text(encoding="utf-8"))
    required = set()
    for actor in catalog["live2d"].values():
        model = actor["model"].removeprefix("res://")
        required.add(model)
        refs = json.loads((root / model).read_text(encoding="utf-8"))["FileReferences"]
        names = [refs["Moc"], *refs["Textures"]]
        names.extend(refs[key] for key in ["Physics", "Pose", "UserData"] if refs.get(key))
        names.extend(row["File"] for row in refs.get("Expressions", []))
        names.extend(row["File"] for rows in refs.get("Motions", {}).values() for row in rows)
        required.update((Path(model).parent / name).as_posix() for name in names)
    entries = list(catalog["spine"])
    if (root / "cg_catalog.json").exists():
        entries += json.loads((root / "cg_catalog.json").read_text(encoding="utf-8"))["groups"]
    for entry in entries:
        required.update(entry[key].removeprefix("res://") for key in ["atlas", "skeleton"])
    return sorted(required)


def prepare(root, output):
    required = required_paths(root)
    missing = [name for name in required if not (root / name).is_file()]
    if missing:
        raise ValueError(f"Missing native source dependencies: {missing}")
    files = sorted(path for path in (root / "assets").rglob("*")
                   if path.is_file() and path.suffix.lower() in SUFFIXES)
    members = {}
    output.mkdir(parents=True, exist_ok=True)
    target = output / "native_payload.zip"
    if target.exists():
        raise FileExistsError(f"Preserve existing payload: {target}")
    with zipfile.ZipFile(target, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=1) as archive:
        for path in files:
            name = path.relative_to(root).as_posix()
            data = path.read_bytes()
            members[name] = {"bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()}
            info = zipfile.ZipInfo(name, date_time=(2026, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(info, data, compresslevel=1)
    assert set(required).issubset(members)
    report = {"files": members, "required_paths": required,
              "archive_sha256": hashlib.sha256(target.read_bytes()).hexdigest()}
    with (output / "native_payload_manifest.json").open("x", encoding="utf-8") as stream:
        json.dump(report, stream, ensure_ascii=False)
    print(json.dumps({"files": len(members), "required": len(required),
                      "archive_bytes": target.stat().st_size, "missing": 0}))


def pack_files(path):
    with path.open("rb") as stream:
        magic, version, major, minor, patch, flags, base = struct.unpack("<6IQ", stream.read(32))
        assert magic == 0x43504447 and version == 2 and not flags & 1
        stream.read(64)
        count = struct.unpack("<I", stream.read(4))[0]
        entries = {}
        for _ in range(count):
            length = struct.unpack("<I", stream.read(4))[0]
            name = stream.read(length).rstrip(b"\0").decode("utf-8").removeprefix("res://")
            offset, size = struct.unpack("<QQ", stream.read(16))
            stream.read(16)
            entry_flags = struct.unpack("<I", stream.read(4))[0]
            assert not entry_flags & 1
            entries[name] = (base + offset, size)
        result = {}
        for name in ["native_payload.zip", "native_payload_manifest.json"]:
            assert name in entries, f"Export omitted {name}"
            offset, size = entries[name]
            stream.seek(offset)
            result[name] = stream.read(size)
        return result


def verify(path):
    files = pack_files(path)
    manifest = json.loads(files["native_payload_manifest.json"])
    assert hashlib.sha256(files["native_payload.zip"]).hexdigest() == manifest["archive_sha256"]
    with zipfile.ZipFile(io.BytesIO(files["native_payload.zip"])) as archive:
        names = set(archive.namelist())
        assert set(manifest["required_paths"]).issubset(names)
        assert names == set(manifest["files"])
        for name, info in manifest["files"].items():
            data = archive.read(name)
            assert len(data) == info["bytes"]
            assert hashlib.sha256(data).hexdigest() == info["sha256"], name
    print(json.dumps({"pack": str(path), "verified_files": len(names),
                      "required_paths": len(manifest["required_paths"]), "missing": 0}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--output", type=Path)
    parser.add_argument("--verify-pack", type=Path)
    args = parser.parse_args()
    if args.verify_pack:
        verify(args.verify_pack)
    else:
        prepare(args.root, args.output or args.root)
