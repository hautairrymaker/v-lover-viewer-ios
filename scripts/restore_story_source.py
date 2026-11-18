"""Verify private source parts and restore only reviewed archive paths."""
import hashlib
import json
import sys
import zipfile
from pathlib import Path


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def restore(source, destination):
    manifest = json.loads((source / "story-source-manifest.json").read_text(encoding="utf-8"))
    combined = source / "restored-source.zip"
    with combined.open("xb") as output:
        for part in manifest["parts"]:
            name = part["name"]
            if Path(name).name != name:
                raise ValueError("Invalid transport filename")
            path = source / name
            if path.stat().st_size != part["bytes"] or digest(path) != part["sha256"]:
                raise ValueError("Transport checksum mismatch")
            with path.open("rb") as stream:
                while data := stream.read(1024 * 1024):
                    output.write(data)
    if digest(combined) != manifest["archive_sha256"]:
        raise ValueError("Combined archive mismatch")
    with zipfile.ZipFile(combined) as archive:
        if set(archive.namelist()) != set(manifest["files"]):
            raise ValueError("Archive file list mismatch")
        for name in archive.namelist():
            target = (destination / name).resolve()
            if not target.is_relative_to(destination.resolve()):
                raise ValueError("Unsafe archive entry")
        archive.extractall(destination)
    for name, info in manifest["files"].items():
        path = destination / name
        if path.stat().st_size != info["bytes"] or digest(path) != info["sha256"]:
            raise ValueError("Restored source mismatch")
    print(json.dumps({"verified_source_files": len(manifest["files"]), "missing": 0}))


if __name__ == "__main__":
    restore(Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve())
