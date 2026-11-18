#!/usr/bin/env bash
# 编译 gd_cubism 的 iOS 动态库。Windows 用的那个 DLL 不能复用。
set -euo pipefail

GD_CUBISM_REF="${GD_CUBISM_REF:-3aaa3c9001808732c40aa3fa07460a95125d9ccc}"
GODOT_CPP_REF="${GODOT_CPP_REF:-godot-4.4.1-stable}"
WORK="${RUNNER_TEMP:-/tmp}/gd_cubism_build"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

rm -rf "$WORK"
git clone --filter=blob:none https://github.com/MizunagiKB/gd_cubism.git "$WORK"
cd "$WORK"
git checkout "$GD_CUBISM_REF"

# 上游 .gitmodules 把 godot-cpp 固定在 4.1 分支，和 4.4.1 模板不匹配，这里换成 4.4.1
git submodule update --init --recursive godot-cpp
cd godot-cpp
git fetch --depth 1 origin "refs/tags/$GODOT_CPP_REF:refs/tags/$GODOT_CPP_REF" || git fetch --depth 1 origin "$GODOT_CPP_REF"
git checkout "$GODOT_CPP_REF"
cd ..

# Cubism Native SDK 由私有素材仓库提供（Live2D 授权不允许公开分发）
SDK_SRC="${CUBISM_SDK_DIR:?需要设置 CUBISM_SDK_DIR 指向 CubismSdkForNative-5-r.1}"
rm -rf thirdparty
mkdir -p thirdparty
cp -R "$SDK_SRC" thirdparty/CubismSdkForNative-5-r.1

echo "== 编译 gd_cubism (ios, arm64, template_release) =="
JOBS="$(sysctl -n hw.ncpu)"
scons platform=ios arch=arm64 target=template_release -j"$JOBS"

mkdir -p "$PROJECT_DIR/addons/gd_cubism/bin"

publish_lib() {
  local token="$1" out="$2" src
  src="$(find demo/addons/gd_cubism/bin -name "*${token}*.dylib" 2>/dev/null | head -n 1)"
  if [ -z "$src" ]; then
    echo "::error::没有找到 ${token} 的 dylib"
    ls -la demo/addons/gd_cubism/bin || true
    exit 1
  fi
  cp "$src" "$PROJECT_DIR/addons/gd_cubism/bin/$out"
  echo "$out <- $src"
}

publish_lib ios libgd_cubism.ios.release.arm64.dylib

# 编辑器宿主是 macOS，必须也编一个 macOS 库，否则导出时 GDCubismUserModel 等类型无法注册，
# main.gd 解析失败，打出来的包在真机上 Live2D 是空的。
echo "== 编译 gd_cubism (macos, arm64) 供导出时加载 =="
scons platform=macos arch=arm64 target=template_release -j"$JOBS"
publish_lib macos libgd_cubism.macos.release.arm64.dylib

echo "== 最终产物 =="
ls -la "$PROJECT_DIR/addons/gd_cubism/bin/"
