# 快乐轻骑 (HappyRide)

被动骑行/运动日志 iOS app：自动检测运动，没有「开始」按钮；另有可选的手动「码表」模式。

## 改代码前必须知道的三件事

### 1. 新增或删除源文件后，必须重新生成项目

```bash
xcodegen generate
```

`project.yml` 是唯一源头，`Bike.xcodeproj` 是生成物（已 gitignore）。
`project.yml` 按目录整个 glob，所以只要跑一次生成，新文件就会自动进对应 target。

**不跑会怎样**：Xcode 报一堆 `Cannot find 'XxxYyy' in scope`，看起来像代码错误，
其实是项目文件里根本没有那个文件。排查起来很浪费时间——2026-09-06 就踩过一次，
一次漏了 4 个文件。

### 2. 本机跑不了 `xcodebuild`，用 typecheck 脚本代替

这台机器的 Xcode 没装对应的 iOS 平台，`xcodebuild` 解析不到 destination。
所以有一个不依赖模拟器的 Swift 6 严格并发类型检查脚本：

```bash
bash scripts/typecheck.sh          # 主 app
bash scripts/typecheck.sh watch    # watchOS app
bash scripts/typecheck.sh tests    # 主 app + Bike/Tests
```

它只保证**能编过**。`Bike/Tests` 里的断言跑不了，要在 Xcode 里 ⌘U 跑。
所以别声称测试通过了——只能说类型检查通过了。

### 3. 领域层是纯 SwiftPM 包，可以直接跑测试

```bash
cd Packages/CyclingDomain && swift test
```

`Packages/CyclingDomain` 不依赖 CoreLocation / CoreMotion / HealthKit，全是纯函数。
**新逻辑优先写在这里**，因为这是唯一能在本机真正跑起断言的地方。
需要系统框架的代码放 `Bike/Sources`，那部分只能靠类型检查 + 真机验证。

## 架构

- `Packages/CyclingDomain` — 纯函数领域层（检测策略、对账、统计、导入筛选）
- `Bike/Sources/Detection` — CoreMotion / CoreLocation / HealthKit / WatchConnectivity
- `Bike/Sources/Persistence` — SwiftData（`RideModel`）+ 映射 + 去重
- `Bike/Sources/UI` — SwiftUI
- `Bike/Sources/Routing` — 路线规划
- `Bike/Sources/Subscription` — StoreKit 2 订阅
- `Bike/Sources/Support` — 格式化等公共工具
- `Bike/Sources/App` — 入口、依赖装配
- `BikeWatch/Sources` — 手表 app
- `BikeWatchWidget/Sources` — 手表小组件

`project.yml` 全局 `SWIFT_VERSION: 6.0`，即 Swift 6 语言模式（默认完整并发检查）；
`Bike` target 另外显式写了 `SWIFT_STRICT_CONCURRENCY: complete`。

## 数据规矩

**传感器没数据就显示没数据，不要推算。** GPS 没动就显示 0，不要拿位移去凑一个
看起来合理的时速；第三方导入的记录，对方没记距离就没有距离、也没有均速。
宁可少显示一个数，也不要显示一个编出来的数。

**导入的记录只读不删。** `RideModel` 有两个 UUID 字段，别搞混：
- `healthKitWorkoutUUID` — **本 app 写进** Apple 健康的 workout，删记录时会连带删它
- `externalWorkoutUUID` — **别人写的**（Garmin / 华为 / Zepp…），只用来防重复导入

把第三方的 UUID 存进第一个字段，会导致用户删本地记录时把人家 Apple 健康里的原始
记录一起删掉。导入的记录也不写回健康——那条 workout 本来就在健康里，写回就是制造重复。

## 本地化

六语言：zh-Hans（源）、en、ja、ko、zh-Hant、de。文案走 `Bike/Sources/Localizable.xcstrings`。

**条目是 Xcode 构建时提取的**，本机跑不了构建，所以新写的 `String(localized:)` /
`Text("…")` 不会自动进表——要么在 Xcode 里构建一次让它提取，要么手工加条目。
key 写错只会回落到中文，不会崩，下次构建 Xcode 会自己对账。

手工加条目时的三条格式约定（都是从既有条目里验证出来的，不要凭感觉写）：

1. **插值的格式符看调用方式，不只看类型**
   - `String(localized: "\(intVar) 分")` → `%lld 分`
   - `Text("约 \(Int(x)) 公里环线")` → `约 %@ 公里环线`（SwiftUI 的 Text 一律 `%@`）
2. **两个以上参数的译文用位置化写法**：key 里是裸的 `%@ … %@`，
   译文里要写 `%1$@ … %2$@`，否则调换语序时会错位。
3. **字面百分号在 key 里是 `%%`**，如 `陡坡 %lld%%`。

改完用这个自查：每条译文的格式符（把 `%1$` 归一成 `%`）必须和 key 完全一致。

## 上架

App Store 每个 locale 的描述**最底部**必须附标准 Apple EULA 链接：
https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
