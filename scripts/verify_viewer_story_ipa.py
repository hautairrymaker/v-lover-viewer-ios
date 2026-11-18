"""Inspect the integrated IPA structurally without rendering or reading dialogue."""
import argparse
import hashlib
import json
import shutil
import struct
import tempfile
import zipfile
from pathlib import Path

from prepare_native_payload import verify

MAGICS = {b"\xcf\xfa\xed\xfe", b"\xfe\xed\xfa\xcf",
          b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca",
          b"\xca\xfe\xba\xbf", b"\xbf\xba\xfe\xca"}


def inspect(ipa, metadata, expected_scenario, output):
    release = json.loads(metadata.read_text(encoding="utf-8"))
    candidates = [asset for asset in release["assets"] if asset["name"] == ipa.name]
    if len(candidates) != 1 or candidates[0]["size"] != ipa.stat().st_size:
        raise ValueError("Release file size/name mismatch")
    with ipa.open("rb") as stream:
        digest = hashlib.file_digest(stream, "sha256").hexdigest()
    expected = candidates[0].get("digest")
    if expected and expected != "sha256:" + digest:
        raise ValueError("Release SHA256 mismatch")
    with tempfile.TemporaryDirectory() as directory:
        pack = Path(directory) / "viewer-story.pck"
        with zipfile.ZipFile(ipa) as archive:
            native = {}
            for prefix in ("libgd_cubism", "libspine_godot.ios.template_release"):
                matches = []
                for name in archive.namelist():
                    if name.rsplit("/", 1)[-1].startswith(prefix):
                        with archive.open(name) as stream:
                            if stream.read(4) in MAGICS:
                                matches.append(name)
                if not matches:
                    raise ValueError("Missing native executable: " + prefix)
                native[prefix] = matches
            packs = [name for name in archive.namelist() if name.endswith(".pck")]
            if len(packs) != 1:
                raise ValueError("Expected exactly one PCK")
            with archive.open(packs[0]) as source, pack.open("xb") as target:
                shutil.copyfileobj(source, target, 1024 * 1024)
        with pack.open("rb") as stream:
            header = struct.unpack("<6IQ", stream.read(32))
            magic, version, _, _, _, flags, base = header
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
                data = stream.read(size)
                if len(data) != size:
                    raise ValueError("Truncated PCK entry")
                return data

            scenario_bytes = read("data/scenario_full.json")
            if hashlib.sha256(scenario_bytes).hexdigest() != expected_scenario:
                raise ValueError("Story source differs from reviewed desktop source")
            scenario = json.loads(scenario_bytes)
            gallery = json.loads(read("data/gallery.json"))
            public = [entry for entry in gallery["cards"] if entry.get("playable")
                      and "*" + entry["label"].removeprefix("*") in scenario["labels"]]
            if len(public) != 25 or "*開場劇情" not in scenario["labels"]:
                raise ValueError("Public chapter catalog mismatch")
            cg = json.loads(read("cg_catalog.json"))["groups"]
            if len(cg) != 25:
                raise ValueError("CG group count mismatch")
            for name in ("main.gd", "scripts/viewer_story_mode.gd",
                         "scripts/story_player_host.gd", "scripts/story.gd",
                         "scripts/story_cg_stage.gd", "scripts/live2d_stage.gd"):
                if name not in entries and name + ".remap" not in entries:
                    raise ValueError("Runtime script missing: " + name)
            assets = json.loads(read("data/assets.json"))
            for path in assets["voice"].values():
                name = path.removeprefix("res://")
                if name not in entries and name + ".import" not in entries:
                    raise ValueError("Story voice missing")
            manifest = json.loads(read("native_payload_manifest.json"))
        verify(pack)
    result = {"ipa_bytes":ipa.stat().st_size, "sha256":digest,
              "release_digest_matched":bool(expected),
              "scenario_sha256":expected_scenario,
              "public_chapters_including_intro":26, "internal_labels":len(scenario["labels"]),
              "cg_groups":len(cg), "story_voice_paths":len(assets["voice"]),
              "native_files":len(manifest["files"]), "native_binaries":native,
              "missing":0, "on_device_and_UV_visual_acceptance":"pending"}
    output.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    print("VIEWER_STORY_IPA_CHECK " + json.dumps(result, ensure_ascii=False))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--ipa", required=True, type=Path)
    parser.add_argument("--metadata", required=True, type=Path)
    parser.add_argument("--scenario-sha256", required=True)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    inspect(args.ipa, args.metadata, args.scenario_sha256, args.output)
