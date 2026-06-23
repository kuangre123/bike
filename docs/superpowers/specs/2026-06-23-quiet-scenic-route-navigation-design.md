# 安静风景路线 + 骑行导航 — 设计文档

- 日期：2026-06-23
- 状态：已通过 brainstorming，待出实现计划
- 范围：iPhone（新「路线」tab）；不涉及 watch

## 1. 概述

给 app 增加第二大功能：**到目的地的安静风景骑行路线 + 逐向导航**。核心诉求：**尽量少走车多的主干道、偏向风景好的路**。用开放的自行车算路引擎 **BRouter**（免费、无 key、自带优先车道/避主干道的 profile）实现。

这是 app 第一个**联网**功能（此前全本地），会把起终点坐标发给第三方地图服务，因此默认关闭、需用户一次性同意。

## 2. 目标 / 非目标

**目标**
- 选目的地（搜索或地图点选）→ 生成一条避开主干道、偏安静/风景的骑行路线
- 路线预览：地图折线 + 距离 + 预计时间
- 逐向导航：转向提示卡 + 地图跟随用户朝向 + 语音播报（可关）+ 偏航自动重算 + 屏幕常亮
- 独立「路线」tab；运动日志仍是第一个 tab，内容不变
- 联网功能默认关，首次使用一次性同意

**非目标（v2+）**
- 风景途经点强化（OSM 公园/河滨）—— MVP 靠安静 profile 近似
- 环线生成（无目的地）
- 离线算路 / 自建 BRouter 服务器
- 多备选路线对比、坡度剖面
- watch 端路线/导航

## 3. 核心决策（来自 brainstorming）

| 维度 | 决策 |
|------|------|
| 产出形态 | 到目的地的安静路线 |
| 算路引擎 | BRouter（公共服务器，`trekking` profile，带 voicehints） |
| 入口 | 独立 tab（根改 TabView） |
| 导航 | 做逐向导航（转向卡 + 跟随 + 语音 + 偏航重算） |
| 「风景」 | MVP 靠安静 profile；途经点留 v2 |
| 隐私 | 联网默认关，首次同意；起终点发往 brouter.de |

## 4. 架构

```
TabView（根）
├── 「运动」 RideTimelineView（现有，不动）
└── 「路线」 RouteFeatureView（新）
        ├── RoutePlannerView   选目的地 + 预览路线
        │     ├── DestinationSearch (MKLocalSearch)
        │     └── RouteService → BRouter → RoutePlan
        └── RideNavigationView 逐向导航
              └── RideNavigator（运行时：定位/进度/偏航/语音）
                    └── 复用 CyclingDomain 纯逻辑
```

**领域层（CyclingDomain，纯函数，重点单测）**
- `RoutePlan`：`coordinates: [Coordinate]`、`distanceMeters`、`estimatedDuration`、`turns: [TurnInstruction]`
- `Coordinate`（lat/lon，避免 CoreLocation 依赖）
- `TurnInstruction`：`coordinateIndex`、`command`（左转/右转/直行/掉头…）、`distanceFromPrevMeters`
- `parseBRouterGeoJSON(_ data:) -> RoutePlan?`：解析 BRouter geojson（几何 + `voicehints` + `track-length`/`total-time`）
- `nearestPointOnRoute(_ loc:, _ coords:) -> (index, distanceMeters)`：定位投影到折线
- `navigationProgress(loc:, plan:) -> NavProgress`：当前最近点、到下一转向距离、下一转向、是否偏航
- `isOffRoute(distanceToRouteMeters:, threshold:)`

**App 层**
- `RouteService`（网络）：构造 `https://brouter.de/brouter?lonlats=...&profile=trekking&alternativeidx=0&format=geojson`，请求、把响应交给 `parseBRouterGeoJSON`，错误/离线处理
- `DestinationSearch`：`MKLocalSearch` 封装，关键词 → 候选地点
- `RoutePlannerView`：搜索栏 + 地图（点选落点）+ 结果卡（距离/时间/「已避主干道」）+「开始导航」
- `RideNavigationView`：地图（朝向跟随）+ 顶部转向卡 + 底部「结束」；`AVSpeechSynthesizer` 语音
- `RideNavigator`（@MainActor @Observable）：CLLocationManager → 每次更新算 `navigationProgress`，推进转向、判偏航（持续偏航→`RouteService` 重算）、必要时播报
- `RoutePrefs`：联网同意开关（UserDefaults / AppStorage），默认关

## 5. 数据流

**规划（R1）**
1. 用户搜索/点选目的地 → 目的地坐标
2. 取当前定位（需 When-In-Use）
3. `RouteService.route(from:to:)` → BRouter geojson → `parseBRouterGeoJSON` → `RoutePlan`
4. 地图画折线 + 起终点 + 距离/时间

**导航（R2）**
1. 「开始导航」→ `RideNavigationView` + `RideNavigator.start(plan:)`
2. 定位更新 → `navigationProgress(loc:, plan:)` → 更新转向卡（下一转向 + 剩余距离）
3. 过转向点 → 推进到下一条；接近转向时语音播报
4. 偏航（离线 > 阈值持续若干秒）→ 重新算路，替换 plan
5. 到终点 → 结束提示

## 6. BRouter 细节

- 请求：`GET https://brouter.de/brouter?lonlats={lon},{lat}|{lon},{lat}&profile=trekking&alternativeidx=0&format=geojson`
- 响应：GeoJSON `LineString`，`properties` 含 `track-length`(m)、`total-time`(s)、`voicehints`（转向：[索引, 指令码, 转角, 距下一提示米数...]）
- 指令码映射到中文转向（左/右/直行/掉头/到达）
- 限流：公共服务器有速率限制 → 请求去抖 + 失败重试 + 缓存上次结果；正式上线自建（留 v2）

## 7. 错误处理

- 无网络 / 服务器错误 / 无路线 → 友好提示 + 重试
- 定位未授权 → 引导授权（复用现有权限模式）
- 偏航重算失败 → 保留原 plan + 提示

## 8. 隐私

- 「路线」首次使用弹一次性同意：说明会联网、把起终点发给 brouter.de
- `RoutePrefs.networkEnabled` 默认 false；设置页可开关
- App Store 隐私说明：位置用于路线规划，发送给第三方地图服务（BRouter）
- Info.plist 定位用途串已具备（When-In-Use）

## 9. 实现分步

- **R1 规划 + 显示**：TabView 改造 + DestinationSearch + RouteService + parseBRouterGeoJSON + RoutePlannerView。领域单测：geojson 解析、长度。
- **R2 逐向导航**：领域 `nearestPointOnRoute`/`navigationProgress`/偏航（重点单测）+ RideNavigator + RideNavigationView + 语音 + 偏航重算。

## 10. 测试

- 领域层充分单测：BRouter geojson 解析、折线长度、最近点投影、偏航判定、转向推进（用样例 geojson 字符串 + 构造坐标，`swift test` 本机可验证）
- 网络与真机导航：手测

## 11. 技术栈

- SwiftUI TabView、MapKit（Map/MapPolyline/朝向跟随）、CoreLocation、AVFoundation（语音）、URLSession（BRouter）
- 纯逻辑在 CyclingDomain（仅 Foundation）
- iOS 17+
