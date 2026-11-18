"""Check exact source patching and UV normalization for resized atlas pages."""
import argparse
import json
import tempfile
from pathlib import Path

from patch_spine_atlas import ORIGINAL, PATCHED, patch


def run(source):
    checks = []
    text = source.read_text(encoding="utf-8")
    prior_patch = (
        "\t\t// Unity keeps authored atlas dimensions when imported textures are resized.\n"
        "\t\tif (page.width == 0 || page.height == 0) {\n"
        "\t\t\tpage.width = texture->get_width();\n"
        "\t\t\tpage.height = texture->get_height();\n"
        "\t\t}"
    )
    if prior_patch in text:
        text = text.replace(prior_patch, ORIGINAL, 1)
    if text.count(ORIGINAL) != 1:
        raise ValueError("Expected pinned original or previously verified patched source")
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        target = root / "spine-godot/spine_godot/SpineAtlasResource.cpp"
        target.parent.mkdir(parents=True)
        target.write_text(text, encoding="utf-8")
        first = patch(root)
        checks.append(first["state"] == "patched")
        checks.append(target.read_text(encoding="utf-8") == text.replace(ORIGINAL, PATCHED, 1))
        second = patch(root)
        checks.append(second["state"] == "already_patched")
        checks.append(first["after_sha256"] == second["after_sha256"])
        target.write_text("unexpected source", encoding="utf-8")
        try:
            patch(root)
        except ValueError:
            checks.append(target.read_text() == "unexpected source")
        else:
            checks.append(False)
    result = {"passed": sum(checks), "failed": len(checks) - sum(checks),
              "source_patch_only": True, "iOS_render_acceptance": "not performed"}
    print(json.dumps(result))
    raise SystemExit(0 if all(checks) else 1)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, required=True)
    run(parser.parse_args().source)
