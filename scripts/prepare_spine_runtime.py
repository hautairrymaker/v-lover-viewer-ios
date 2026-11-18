"""Reproduce the source copy performed by upstream build/setup-extension.sh."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil


def prepare(root):
    godot = root / "spine-godot"
    source = root / "spine-cpp/spine-cpp"
    destination = godot / "spine_godot/spine-cpp"
    for name in ["include/spine/Extension.h", "include/spine/Animation.h",
                 "src/spine/Extension.cpp", "src/spine/Animation.cpp"]:
        if not (source / name).is_file():
            raise RuntimeError(f"Missing pinned spine-cpp source: {source / name}")
    construct = (godot / "SConstruct").read_text(encoding="utf-8")
    for pattern in ["spine_godot/spine-cpp/include", "spine_godot/spine-cpp/src/spine/*.cpp"]:
        if pattern not in construct:
            raise RuntimeError(f"Unexpected upstream build layout: {pattern}")
    copied = 0
    for path in source.rglob("*"):
        if not path.is_file():
            continue
        target = destination / path.relative_to(source)
        if target.exists():
            if path.read_bytes() != target.read_bytes():
                raise RuntimeError(f"Preserved differing existing file: {target}")
        else:
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(path, target)
        assert hashlib.sha256(path.read_bytes()).digest() == hashlib.sha256(target.read_bytes()).digest()
        copied += 1
    result = {"files_verified": copied,
              "cpp_sources": len(list((destination / "src/spine").glob("*.cpp"))),
              "headers": len(list((destination / "include/spine").glob("*.h"))),
              "SConstruct_sha256": hashlib.sha256((godot / "SConstruct").read_bytes()).hexdigest()}
    assert result["cpp_sources"] > 0 and result["headers"] > 0
    print(json.dumps(result))
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("checkout", type=Path)
    prepare(parser.parse_args().checkout)
