# V-Lover Character Studio — iOS

把交接包里的 Godot 查看器做成 iOS 版。**这个仓库只放源码和构建链，不放任何版权素材。**

素材与 Live2D Native SDK 放在一个私有仓库里，由 CI 用 `ASSETS_TOKEN` 拉取。

## 需要配置

| 名称 | 类型 | 值 |
| --- | --- | --- |
| `ASSETS_TOKEN` | Secret | 能读私有素材仓库的 PAT（fine-grained 就给 Contents: Read） |
| `ASSETS_REPO` | Variable | `owner/repo`，如 `hautairrymaker/v-lover-viewer-assets` |

私有素材仓库结构：

```
project/                  # 直接铺到工程根
  assets/
  Portraits/              # 只要 idol1.png idol2.png idol3.png
  catalog.json
  cg_catalog.json
  cg_manifest.json
  cg_voices.json
vendor/
  CubismSdkForNative-5-r.1/
```

## 产物

`V-Lover-Viewer-unsigned.ipa` —— 无签名，需自己用证书重签（Sideloadly / AltStore / Xcode 均可）。

## 为什么不像 vlover-godot 那样 stash gdextension

`vlover-godot` 的 `build-7` 之所以「成功」，是因为导出前把 `cubism.gdextension` 整个移走了，
导出里没有任何原生扩展。包能装，但没有 Live2D、没有 Spine。

这里的做法是：CI 里真的用 Cubism Native SDK 编 `libgd_cubism.ios.release.arm64.dylib`，
并在 `.app` 里断言它存在，缺了就 fail，不拿「导出成功」冒充「能用」。

## 已知限制

- Spine 的 iOS 库是现场编上游 `spine-runtimes` 4.2；原 Windows 库是 `atlas-fixed` 本地补丁版，
  atlas 格式可能与上游不一致，CG 模式需要真机验证。
- Spine 编译失败不会阻断构建：`main.gd` 用 `ClassDB.instantiate` 反射调用，
  缺 Spine 时只降级 CG/Spine 模式，Live2D 与立绘仍可用。
