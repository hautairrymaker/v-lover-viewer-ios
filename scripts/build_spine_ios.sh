#!/usr/bin/env bash
# Build pinned Spine sources and verify both device and editor-host frameworks.
set -euo pipefail

SPINE_REF="${SPINE_REF:-5cb78e77d3711ddcd80c7bd043bb11cf70fcc88c}"
GODOT_CPP_REF="${GODOT_CPP_REF:-e4b7c25e721ce3435a029087e3917a30aa73f06b}"
WORK="$(mktemp -d "${RUNNER_TEMP:-/tmp}/spine_build.XXXXXX")"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
JOBS="$(sysctl -n hw.ncpu)"

git init "$WORK"
git -C "$WORK" remote add origin https://github.com/EsotericSoftware/spine-runtimes.git
git -C "$WORK" fetch --depth 1 origin "$SPINE_REF"
# SConstruct derives CFBundleVersion from the branch name; detached HEAD is invalid.
git -C "$WORK" switch -c 4.2 FETCH_HEAD
test "$(git -C "$WORK" rev-parse HEAD)" = "$SPINE_REF"
cd "$WORK"

GD_DIR="$WORK/spine-godot"
if [ ! -d "$GD_DIR" ]; then
  echo "::warning::spine-runtimes $SPINE_REF 里找不到 spine-godot 目录"
  ls -la
  exit 1
fi
echo "spine-godot: $GD_DIR"
ls -la "$GD_DIR"
cd "$GD_DIR"

# Match the Godot 4.4.1 bindings by immutable commit.
git init godot-cpp
git -C godot-cpp remote add origin https://github.com/godotengine/godot-cpp.git
git -C godot-cpp fetch --depth 1 origin "$GODOT_CPP_REF"
git -C godot-cpp switch --detach FETCH_HEAD
test "$(git -C godot-cpp rev-parse HEAD)" = "$GODOT_CPP_REF"
python3 "$PROJECT_DIR/scripts/prepare_spine_runtime.py" "$WORK"
echo "godot-cpp: $(git -C godot-cpp describe --tags --always 2>/dev/null || echo unknown)"

if [ -f SConstruct ]; then
  scons platform=ios arch=arm64 target=template_release -j"$JOBS"
elif [ -f CMakeLists.txt ]; then
  echo "::warning::spine-godot 使用 CMake，当前脚本未覆盖"
  exit 1
else
  echo "::warning::既没有 SConstruct 也没有 CMakeLists.txt"
  exit 1
fi

mkdir -p "$PROJECT_DIR/addons/spine_godot/bin"
publish_framework() {
  local platform="$1"
  local name="libspine_godot.${platform}.template_release"
  local artifact="bin/${platform}/${name}.framework"
  test -f "$artifact/$name"
  lipo -verify_arch arm64 "$artifact/$name"
  nm -gU "$artifact/$name" > "$WORK/${platform}-symbols.txt"
  grep -q '_spine_godot_library_init' "$WORK/${platform}-symbols.txt"
  plutil -lint "$(find "$artifact" -name Info.plist -print -quit)"
  ditto "$artifact" "$PROJECT_DIR/addons/spine_godot/bin/$(basename "$artifact")"
}
publish_framework ios
# Host library is required to verify real class registration during export.
scons platform=macos arch=arm64 target=template_release -j"$JOBS"
publish_framework macos
cat > "$PROJECT_DIR/spine_godot_extension.gdextension" <<EOF
[configuration]

entry_symbol = "spine_godot_library_init"
compatibility_minimum = "4.1"

[libraries]

ios.release.arm64 = "addons/spine_godot/bin/libspine_godot.ios.template_release.framework"
macos.release.arm64 = "addons/spine_godot/bin/libspine_godot.macos.template_release.framework"
macos.debug.arm64 = "addons/spine_godot/bin/libspine_godot.macos.template_release.framework"
macos.editor.arm64 = "addons/spine_godot/bin/libspine_godot.macos.template_release.framework"
EOF
echo "Spine iOS and macOS frameworks verified."
