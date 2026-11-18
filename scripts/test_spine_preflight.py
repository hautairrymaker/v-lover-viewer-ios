"""Offline checks; never starts GitHub Actions or performs an Apple build."""
import argparse
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument("--source", type=Path, required=True)
parser.add_argument("--bash", type=Path, required=True)
args = parser.parse_args()
scripts = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("prepare", scripts / "prepare_spine_runtime.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
checks = []

with tempfile.TemporaryDirectory(prefix="spine_preflight_") as directory:
    fixture = Path(directory)
    shutil.copytree(args.source / "spine-cpp/spine-cpp", fixture / "spine-cpp/spine-cpp")
    (fixture / "spine-godot").mkdir()
    shutil.copyfile(args.source / "spine-godot/SConstruct", fixture / "spine-godot/SConstruct")
    result = module.prepare(fixture)
    checks.append({"check": "official_source_layout_prepared", "ok": result["cpp_sources"] > 50})
    repeated = module.prepare(fixture)
    checks.append({"check": "idempotent_hash_verified", "ok": repeated == result})
    target = fixture / "spine-godot/spine_godot/spine-cpp/include/spine/Extension.h"
    # Deliberate fixture corruption; user assets and original sources stay untouched.
    target.write_text("corrupt test fixture", encoding="utf-8")
    try:
        module.prepare(fixture)
        checks.append({"check": "preserves_conflicting_file", "ok": False})
    except RuntimeError:
        checks.append({"check": "preserves_conflicting_file", "ok": target.read_text() == "corrupt test fixture"})
    source_header = fixture / "spine-cpp/spine-cpp/include/spine/Animation.h"
    source_header.unlink()
    try:
        module.prepare(fixture)
        checks.append({"check": "missing_dependency_fails", "ok": False})
    except RuntimeError:
        checks.append({"check": "missing_dependency_fails", "ok": True})

syntax = subprocess.run([str(args.bash), "-n", str(scripts / "build_spine_ios.sh")],
                        capture_output=True, text=True)
checks.append({"check": "bash_syntax", "ok": syntax.returncode == 0,
               "exit": syntax.returncode, "stderr": syntax.stderr})
workflow = (scripts.parent / ".github/workflows/ios.yml").read_text(encoding="utf-8")
checks.append({"check": "manual_trigger_only", "ok": "workflow_dispatch:" in workflow and "\n  push:" not in workflow})
checks.append({"check": "spine_failure_blocks_release", "ok": "continue-on-error" not in workflow})
checks.append({"check": "spine_before_cubism", "ok": workflow.index("bash scripts/build_spine_ios.sh") < workflow.index("run: bash scripts/build_cubism_ios.sh")})
checks.append({"check": "real_class_registration_gate", "ok": "res://scripts/check_native_extensions.gd" in workflow})
checks.append({"check": "app_framework_gate", "ok": "test -f \"$SPINE\"" in workflow})
result = {"passed": sum(c["ok"] for c in checks), "total": len(checks), "checks": checks,
          "cloud_runs_triggered": 0, "iOS_compilation": "not performed on Windows"}
print(json.dumps(result))
raise SystemExit(0 if all(c["ok"] for c in checks) else 1)
