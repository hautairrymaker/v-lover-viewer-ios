"""Preserve authored UV dimensions when atlas page textures were resized."""
import argparse
import hashlib
import json
from pathlib import Path

ORIGINAL = (
    "\t\tpage.width = texture->get_width();\n"
    "\t\tpage.height = texture->get_height();"
)
PATCHED = (
    "\t\t// Keep authored atlas dimensions for resized page textures.\n"
    "\t\tif (page.width == 0 || page.height == 0) {\n"
    "\t\t\tpage.width = texture->get_width();\n"
    "\t\t\tpage.height = texture->get_height();\n"
    "\t\t}"
)


def patch(root):
    path = root / "spine-godot/spine_godot/SpineAtlasResource.cpp"
    before = path.read_bytes()
    text = before.decode("utf-8").replace("\r\n", "\n")
    if PATCHED in text:
        state = "already_patched"
    elif text.count(ORIGINAL) == 1:
        newline = "\r\n" if b"\r\n" in before else "\n"
        path.write_bytes(text.replace(ORIGINAL, PATCHED, 1).replace("\n", newline).encode("utf-8"))
        state = "patched"
    else:
        raise ValueError("Unexpected atlas loader source; refusing an unreviewed change")
    result = {"state": state, "before_sha256": hashlib.sha256(before).hexdigest(),
              "after_sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
    print(json.dumps(result))
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("checkout", type=Path)
    patch(parser.parse_args().checkout)
