# 隐私政策 / Privacy Policy

**快乐轻骑 (HappyRide)** — 最后更新 / Last updated: 2026-07-02

## 中文

「快乐轻骑」以隐私优先为设计原则。

### 我们不收集你的数据

- 你的运动记录（时间、距离、速度、路线轨迹、心率、卡路里）**全部只保存在你的设备本地**与你的 iCloud/Apple 健康中，开发者无法访问。
- App **没有账号系统、没有分析统计 SDK、没有广告 SDK、不含任何追踪器**。
- 我们不运营任何收集用户数据的服务器。

### 设备权限的用途

- **运动与健身（CoreMotion）**：在设备本地识别骑行/步行/跑步等运动状态，用于自动记录。数据不离开设备。
- **定位**：记录运动时的距离、速度与路线轨迹；「始终」定位权限用于在你开始骑行时自动唤醒记录。位置数据仅存于设备本地。
- **Apple 健康（HealthKit）**：读取心率用于识别运动；将检测到的运动（含路线、卡路里）写回 Apple 健康。健康数据受 Apple 健康隐私保护，不会被上传。

### 路线规划功能的联网说明

路线规划与导航为可选功能，**默认关闭**。启用前会明确征得你的同意。启用后，规划路线时会把**起点与目的地坐标**发送给开源路线计算服务（brouter.de，位于德国）用于计算骑行路线。该请求即算即回，我们不存储；坐标不与任何身份信息关联。除此之外 App 不进行任何网络通信。

### 订阅

订阅购买与恢复完全通过 Apple 的 App Store（StoreKit）完成，我们不经手也无法看到你的支付信息。

### 联系方式

如有隐私相关问题，请在 GitHub 提交 issue：<https://github.com/kuangre123/bike/issues>

---

## English

**HappyRide** is built privacy-first.

### We do not collect your data

- Your activity records (time, distance, speed, GPS routes, heart rate, calories) **stay on your device** and in your own iCloud / Apple Health. The developer has no access to them.
- The app has **no accounts, no analytics SDKs, no ads, and no trackers**.
- We do not operate any server that collects user data.

### How device permissions are used

- **Motion & Fitness (CoreMotion)**: recognizes cycling/walking/running on-device for automatic recording. Data never leaves your device.
- **Location**: records distance, speed and route while you ride; "Always" permission lets the app wake up automatically when a ride starts. Location data is stored locally only.
- **Apple Health (HealthKit)**: reads heart rate to help detect workouts; writes detected workouts (incl. routes and calories) back to Apple Health. Health data is protected by Apple Health and never uploaded.

### Networking used by the optional route planner

Route planning & navigation is an optional feature, **off by default**, and asks for your explicit consent before enabling. When you plan a route, the **start and destination coordinates** are sent to the open-source routing service (brouter.de, Germany) solely to compute the route. Requests are processed transiently; we store nothing, and coordinates are not linked to any identity. The app performs no other network communication.

### Subscriptions

Purchases and restores are handled entirely by Apple's App Store (StoreKit). We never see your payment information.

### Contact

For privacy questions, please open an issue: <https://github.com/kuangre123/bike/issues>
