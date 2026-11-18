#!/usr/bin/env bash
# 尽力编译 spine-godot 的 iOS 库。上游产物命名不稳定，所以编完用 find 找回并自适应生成 .gdextension。
# 失败不阻断构建：main.gd 用的是运行时反射，缺 Spine 只会降级 CG/Spine 模式。
set -euo pipefail

SPINE_REF="${SPINE_REF:-4.2}"
WORK="${RUNNER_TEMP:-/tmp}/spine_runtimes"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
JOBS="$(sysctl -n hw.ncpu)"

rm -rf "$WORK"
git clone --depth 1 --branch "$SPINE_REF" --recurse-submodules --shallow-submodules \
  https://github.com/EsotericSoftware/spine-runtimes.git "$WORK"
cd "$WORK"

GD_DIR="$(find . -maxdepth 2 -type d \( -name 'spine-godot' -o -name 'spine_godot' \) | head -n 1)"
if [ -z "$GD_DIR" ]; then
  echo "::warning::spine-runtimes $SPINE_REF 里找不到 spine-godot 目录"
  ls -la
  exit 1
fi
echo "spine-godot: $GD_DIR"
ls -la "$GD_DIR"
cd "$GD_DIR"

# spine-godot 内部的 godot-cpp 是嵌套子模块，--recurse-submodules 不会递归到这一层，需显式初始化
git submodule update --init --recursive

# 把 godot-cpp 切到 4.4.1，匹配 Godot 4.4.1 模板（否则 ABI 不匹配，真机加载会失败）
if [ -d godot-cpp ]; then
  cd godot-cpp
  git fetch --depth 1 origin "refs/tags/godot-4.4.1-stable:refs/tags/godot-4.4.1-stable" 2>/dev/null \
    || git fetch --depth 1 origin godot-4.4.1-stable 2>/dev/null || true
  git checkout godot-4.4.1-stable 2>/dev/null || echo "::warning::godot-cpp 切 4.4.1 失败，沿用当前版本"
  cd ..
else
  echo "::warning::spine-godot 下没有 godot-cpp 目录，检查子模块布局"
fi

if [ -f SConstruct ]; then
  scons platform=ios arch=arm64 target=template_release -j"$JOBS"
elif [ -f CMakeLists.txt ]; then
  echo "::warning::spine-godot 使用 CMake，当前脚本未覆盖"
  exit 1
else
  echo "::warning::既没有 SConstruct 也没有 CMakeLists.txt"
  exit 1
fi

ART="$(find . \( -name '*.dylib' -o -name '*.framework' -o -name '*.a' \) | grep -i ios | head -n 1 || true)"
if [ -z "$ART" ]; then
  echo "::warning::spine-godot 编译后没有找到 iOS 产物"
  find . \( -name '*.dylib' -o -name '*.framework' -o -name '*.a' \) | head -n 20 || true
  exit 1
fi

mkdir -p "$PROJECT_DIR/addons/spine_godot/bin"
rm -rf "$PROJECT_DIR/addons/spine_godot/bin/"*
cp -R "$ART" "$PROJECT_DIR/addons/spine_godot/bin/"
NAME="$(basename "$ART")"
cat > "$PROJECT_DIR/spine_godot_extension.gdextension" <<EOF
[configuration]

entry_symbol = "spine_godot_library_init"
compatibility_minimum = "4.1"

[libraries]

ios.release.arm64 = "addons/spine_godot/bin/$NAME"
EOF
echo "已发布 Spine iOS 产物: $NAME"
