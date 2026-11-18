"""Verify raw file inputs in a Godot v2 PCK without interpreting media."""
import hashlib
import json
import struct
import sys
from pathlib import Path


def verify(pack, root):
    entries = {}
    with pack.open("rb") as stream:
        def number(fmt):
            return struct.unpack(fmt, stream.read(struct.calcsize(fmt)))[0]

        if stream.read(4) != b"GDPC" or number("<I") != 2:
            raise ValueError("Expected Godot v2 PCK")
        stream.read(12)
        flags = number("<I")
        base = number("<Q")
        stream.read(64)
        if flags & 1:
            raise ValueError("Encrypted directory unsupported")
        for _ in range(number("<I")):
            name = stream.read(number("<I")).rstrip(b"\0").decode("utf-8")
            offset, size = number("<Q"), number("<Q")
            digest = stream.read(16)
            entry_flags = number("<I")
            entries[name.removeprefix("res://")] = (base + offset, size, digest, entry_flags)
        checked = 0
        imported = 0
        archived = {}
        if "native_payload_manifest.json" in entries:
            start, length, _, _ = entries["native_payload_manifest.json"]
            stream.seek(start)
            archived = json.loads(stream.read(length))["files"]
        suffixes = {".json", ".atlas", ".spine-json", ".spjson", ".skel",
                    ".moc3", ".png", ".ogg", ".wav", ".mp3", ".csv", ".txt"}
        for source in root.rglob("*"):
            relative = source.relative_to(root)
            if any(part.startswith(".") for part in relative.parts):
                continue
            if relative.parts[0] in {"build", "vendor", "scripts"}:
                continue
            if not source.is_file() or source.suffix.lower() not in suffixes:
                continue
            key = relative.as_posix()
            if key not in entries:
                if key in archived:
                    if (source.stat().st_size != archived[key]["bytes"]
                            or hashlib.file_digest(source.open("rb"), "sha256").hexdigest()
                            != archived[key]["sha256"]):
                        raise ValueError("Archived source mismatch: " + key)
                    checked += 1
                    continue
                if source.suffix.lower() in {".png", ".ogg", ".wav", ".mp3"}:
                    if key + ".import" in entries:
                        imported += 1
                        continue
                raise ValueError("Missing raw input: " + key)
            offset, size, digest, entry_flags = entries[key]
            if entry_flags & 1 or size != source.stat().st_size:
                raise ValueError("Size/encryption mismatch: " + key)
            stream.seek(offset)
            actual = hashlib.md5()
            remaining = size
            with source.open("rb") as original:
                while remaining:
                    chunk = stream.read(min(1048576, remaining))
                    if not chunk or chunk != original.read(len(chunk)):
                        raise ValueError("Content mismatch: " + key)
                    actual.update(chunk)
                    remaining -= len(chunk)
            if actual.digest() != digest:
                raise ValueError("PCK digest mismatch: " + key)
            checked += 1
    if not checked and not imported:
        raise ValueError("No raw inputs checked")
    print(json.dumps({"checked_raw_files": checked, "imported_media": imported, "missing": 0}))


if __name__ == "__main__":
    verify(Path(sys.argv[1]), Path(sys.argv[2]))
