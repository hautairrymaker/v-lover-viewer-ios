"""Pin the actual Godot platform feature method bodies used by the path fix."""
import argparse
import hashlib
import json
import urllib.request
from pathlib import Path

FILES = {
    "os.cpp": ("core/os/os.cpp", ("String OS::get_identifier() const", "bool OS::has_feature(")),
    "os_ios.mm": ("platform/ios/os_ios.mm", (
        "String OS_IOS::get_name() const", "bool OS_IOS::_check_internal_feature_support(")),
}


def method(text, signature):
    start = text.index(signature)
    brace = text.index("{", start)
    depth = 0
    for index in range(brace, len(text)):
        if text[index] == "{":
            depth += 1
        elif text[index] == "}":
            depth -= 1
            if depth == 0:
                return text[start:index + 1]
    raise ValueError("Incomplete method body")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--source-directory", type=Path)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=False)
    report = {"version":"4.4.1-stable", "files":{}}
    for filename, (relative, signatures) in FILES.items():
        url = "https://raw.githubusercontent.com/godotengine/godot/4.4.1-stable/" + relative
        if args.source_directory:
            data = (args.source_directory / filename).read_bytes()
        else:
            with urllib.request.urlopen(url, timeout=30) as response:
                data = response.read()
        (args.output / filename).write_bytes(data)
        text = data.decode("utf-8")
        report["files"][relative] = {
            "url":url, "sha256":hashlib.sha256(data).hexdigest(),
            "methods":{signature:method(text, signature) for signature in signatures},
        }
    bodies = report["files"]["core/os/os.cpp"]["methods"]
    assert "get_name().to_lower()" in bodies["String OS::get_identifier() const"]
    assert "p_feature == get_identifier()" in bodies["bool OS::has_feature("]
    report["checks"] = {"lowercase_identifier":True, "feature_compared_without_case_folding":True}
    (args.output / "source-audit.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps({"checks":report["checks"],
        "source_sha256":{name:row["sha256"] for name,row in report["files"].items()}}))
