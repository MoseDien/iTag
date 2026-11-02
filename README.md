# iTag

基于 **SwiftUI + TCA（The Composable Architecture）+ Tuist** 的 iOS 打卡应用。

## 功能

- **打卡页**：全屏地图展示当前位置，自动反地理编码地名，可填备注后一键打卡
- **历史页**
  - 记录列表：按天分组，滑动删除
  - 地图总览：最近一周 / 一个月 / 一个季度 / 一年的打卡点全部落到一张地图上

## 项目标识

- **Bundle Identifier**：`com.belldien.itag`（定义于 `Tuist/ProjectDescriptionHelpers/ProjectFactory.swift` 的 `appBundleId`，各模块由它派生，改一处全局生效）
- 最低部署版本：iOS 17.0（iPhone / iPad）

## iCloud 同步

打卡记录与照片通过 **CloudKit 私有库**在多设备间同步（`CloudSync` 模块）：

- 一条打卡 = 一条 `CheckIn` CKRecord，照片以 `CKAsset` 随记录上下行
- 合并策略：LWW（`updatedAt` 新者胜）；本地删除以墓碑记录，下次同步时对云端清算
- 历史页导航栏云图标指示状态：同步中 / 已同步 / 失败 / 未启用
- **启用条件**：Xcode 中为 iTag target 选择签名 Team（entitlements 已配置 `iCloud.com.belldien.itag` 容器），并在设备/模拟器登录 iCloud；未登录时自动降级为纯本地模式
- 首次运行后需在 [CloudKit Dashboard](https://icloud.developer.apple.com) 的开发环境部署 `CheckIn`/`Meta` record schema（首次 save 会自动创建）

## 模块结构

```
App             AppFeature / RootView（组合两个 Tab）
├─ FeatureCheckIn    打卡页 Reducer + View（+ 单测）
├─ FeatureHistory    历史列表 + 历史地图（+ 单测）
├─ CoreClients       LocationClient / GeocodingClient / CheckInClient（JSON 持久化）
└─ Domain            CheckIn 模型 / TimeRange / 纯过滤分组逻辑（+ 单测）
```

依赖自上而下单向传递；外部依赖为 SPM 的 `swift-composable-architecture` 与 `swift-dependencies`。

## 常用命令

```bash
mise install                  # 安装 .mise.toml 固定的 Tuist
mise exec -- tuist install    # 拉取 SPM 依赖（首次或 Package.swift 变更后）
mise exec -- tuist generate   # 生成 iTag.xcworkspace
mise exec -- tuist test       # 跑全部单测
```

日常开发：用 Xcode 打开 `iTag.xcworkspace`，选 iTag scheme ⌘R 运行。

## 模拟器调试定位

Xcode 菜单 **Features → Location → Custom Location** 设置坐标；反地理编码需联网。

## 数据

打卡记录以 JSON 数组存于 App 沙盒 `Documents/checkins.json`（ISO8601 时间，原子写入）。
