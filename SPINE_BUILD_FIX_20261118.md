# Spine 编译修复，2026-11-18

本次只修改本地文件。没有提交、push、触发Actions或上传IPA，
云编译消耗0次。不是iOS编译成功的声明。

## 已确认根因

旧脚本完整克隆spine-runtimes，但漏掉官方准备步骤：
`spine-godot/build/setup-extension.sh` 中：

```bash
cp -r ../spine-cpp/spine-cpp spine_godot
```

因此SConstruct要求的 `spine_godot/spine-cpp/include` 和
`spine_godot/spine-cpp/src/spine/*.cpp` 不存在。
不是再克隆一次完整仓库就能修复。

固定Spine：5cb78e77d3711ddcd80c7bd043bb11cf70fcc88c。
固定Godot4.4.1绑定：e4b7c25e721ce3435a029087e3917a30aa73f06b。
来源：EsotericSoftware/spine-runtimes与godotengine/godot-cpp
官方GitHub API及已下载同SHA源码。非REA/非原Unity方法证据。

## 已修改

- scripts/prepare_spine_runtime.py：补齐官方目录准备，核验
  158文件、67份CPP、91份头文件；冲突保留并报错。
- scripts/build_spine_ios.sh：固定源码；独立临时目录保留；
  iOS和macOS编辑器各编译一份；只取SConstruct确定的framework，
  核验arm64、导出入口符号和plist；不再随机find第一个库。
  分支名4.2保证上游生成合法4.2.0 bundle版本，避免HEAD.0。
- scripts/check_native_extensions.gd：实际检测Live2D与Spine类注册。
- .github/workflows/ios.yml：只允许手动触发；Spine先编译，
  失败立即终止，不再发布缺Spine的包；严格保留导入/导出退出码；
  app内必须有Spine framework和入口符号才允许打包。
- scripts/test_spine_preflight.py：本地依赖布局/冲突/缺文件/
  Bash语法和流程门禁验证。不会启动云构建。

## 本地结果及限制

首轮10/10，子/包装器0/0、stderr空；
回执在主工程 evidence/rea_connection_20261117/spine_ios_preflight_run01。
最终run02 PID41584：10/10，子/包装器0/0，stderr空；
run01 PID12140及run02末核均已退出。
源文件均在临时fixture验证，未修改原下载源码。
git diff --check通过，无提交和push。
额外YAML解析尝试因本地缺PyYAML报ModuleNotFoundError/退出1，
未宣称完整YAML解析通过；已检查修改处缩进和流程文本。

Windows无Apple SDK，尚未实际运行scons iOS/macOS或xcodebuild。
未验证新IPA/真机/全部CG视觉。不能承诺剩余一次一定成功。
旧build-11保持原样，Live2D构建脚本未改。

## 给云端接手者

使用本目录修改后的源码，先查看git diff及未跟踪的新scripts文件，
不要只上传两个已跟踪文件，否则prepare/check脚本缺失。
本地说明中的10/10不是云编译通过数。
不要恢复push自动构建，不要把Spine改回continue-on-error。
下一次手动构建会先验证Spine，失败在该步停止，查看该步完整日志。
只有Spine编译、编辑器类注册、app库检查都通过，才会发布完整候选IPA。
