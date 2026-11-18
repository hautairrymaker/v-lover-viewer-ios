"""Inspect a released IPA without rendering, modifying, or signing it."""
import argparse
import hashlib
import json
import struct
import tempfile
import zipfile
from pathlib import Path

from prepare_native_payload import verify


def inspect(ipa, expected_sha256, expected_cues, output):
    with ipa.open("rb") as stream:
        digest = hashlib.file_digest(stream, "sha256").hexdigest()
    if digest != expected_sha256:
        raise ValueError("Released IPA checksum mismatch")
    with tempfile.TemporaryDirectory() as temporary:
        pack = Path(temporary) / "viewer.pck"
        with zipfile.ZipFile(ipa) as archive:
            names = archive.namelist()
            if not any("libgd_cubism" in name and name.endswith(".dylib") for name in names):
                raise ValueError("Live2D library missing")
            if not any(name.endswith("libspine_godot.ios.template_release") for name in names):
                raise ValueError("Spine library missing")
            packs = [name for name in names if name.endswith(".pck")]
            if len(packs) != 1:
                raise ValueError("Expected one resource pack")
            with archive.open(packs[0]) as source, pack.open("xb") as target:
                while data := source.read(1024 * 1024):
                    target.write(data)
        with pack.open("rb") as stream:
            magic, version, major, minor, patch, flags, base = struct.unpack("<6IQ", stream.read(32))
            if magic != 0x43504447 or version != 2 or flags & 1:
                raise ValueError("Unsupported resource pack")
            stream.read(64)
            entries = {}
            for _ in range(struct.unpack("<I", stream.read(4))[0]):
                length = struct.unpack("<I", stream.read(4))[0]
                name = stream.read(length).rstrip(b"\0").decode().removeprefix("res://")
                offset, size = struct.unpack("<QQ", stream.read(16))
                stream.read(16)
                entry_flags = struct.unpack("<I", stream.read(4))[0]
                if entry_flags & 1:
                    raise ValueError("Encrypted resource entry")
                entries[name] = (base + offset, size)

            def read(name):
                offset, size = entries[name]
                stream.seek(offset)
                return stream.read(size)

            subtitles = json.loads(read("cg_subtitles.json"))
            voice_bytes = read("cg_voices.json")
            voices = json.loads(voice_bytes)["cues"]
            if hashlib.sha256(voice_bytes).hexdigest() != subtitles["source_sha256"]["voices"]:
                raise ValueError("Subtitle index refers to different voice catalog")
            if len(voices) != expected_cues:
                raise ValueError("Unexpected voice cue count")
            for cue in voices:
                caption = subtitles["subtitles"].get(str(cue["op_index"]))
                if not isinstance(caption, str) or not caption.strip():
                    raise ValueError("Missing caption")
            if not {"voice_subtitle.gd", "voice_subtitle.gd.remap"}.intersection(entries):
                raise ValueError("Subtitle script missing")
            manifest = json.loads(read("native_payload_manifest.json"))
        verify(pack)
    result = {"bytes": ipa.stat().st_size, "sha256": digest,
              "voice_cues": len(voices), "subtitles_matched": len(voices), "missing": 0,
              "native_files": len(manifest["files"]),
              "required_native_paths": len(manifest["required_paths"]),
              "live2d_library_present": True, "spine_library_present": True,
              "on_device_acceptance": "pending"}
    output.write_text(json.dumps(result, indent=2), encoding="utf-8")
    print(json.dumps(result))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--ipa", type=Path, required=True)
    parser.add_argument("--sha256", required=True)
    parser.add_argument("--cues", type=int, default=855)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    inspect(args.ipa, args.sha256, args.cues, args.output)
