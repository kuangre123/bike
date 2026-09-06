import SwiftUI

/// 设置：权限状态 + 手动同步（M3 调试 / 演示用）。
struct SettingsView: View {
    @Environment(PermissionsManager.self) private var permissions
    @Environment(RideDetectionCoordinator.self) private var coordinator
    @Environment(ExternalWorkoutImporter.self) private var externalImporter
    @Environment(\.dismiss) private var dismiss
    @AppStorage("healthWriteBack") private var healthWriteBack = true
    @AppStorage("ebikeAutoFlag") private var ebikeAutoFlag = true
    @AppStorage("weeklyGoalKm") private var weeklyGoalKm: Double = 30
    @AppStorage("overspeedAlertKmh") private var overspeedAlertKmh: Double = 0
    @AppStorage("recordWalking") private var recordWalking = true
    @AppStorage("recordEBike") private var recordEBike = true
    @AppStorage("recordOther") private var recordOther = true
    @State private var duplicateCleanupMessage: String?
    @State private var isCleaningDuplicates = false
    /// 勾选状态存在 UserDefaults 里（`ExternalSourcePreferences`），这里只是让视图跟着刷新。
    @State private var enabledSourceIDs = ExternalSourcePreferences.enabledSourceIDs
    @StateObject private var subscription = SubscriptionManager.shared
    @State private var showPaywall = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if subscription.isPro {
                        Label("轻骑运动 Pro 已激活", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button { showPaywall = true } label: {
                            Label("升级 轻骑运动 Pro", systemImage: "crown.fill")
                        }
                    }
                    Button("恢复购买") { Task { await subscription.restore() } }
                } header: {
                    Text("订阅")
                } footer: {
                    Text("Pro 解锁安静风景路线推荐、逐向导航与高级统计。")
                }

                Section("权限") {
                    LabeledContent("运动与健身", value: motionText)
                    LabeledContent("定位", value: locationText)
                    Button("请求权限") { permissions.requestAll() }
                }
                Section {
                    Button("同步运动数据") {
                        Task { await coordinator.runReconciliation() }
                    }
                    if let last = coordinator.lastReconcileDate {
                        LabeledContent("上次同步", value: last.formatted(date: .omitted, time: .standard))
                    }
                    LabeledContent("本次会话已保存", value: "\(coordinator.savedRideCount)")
                    Toggle("自动标注疑似电动车", isOn: $ebikeAutoFlag)
                    Picker("超速提醒", selection: $overspeedAlertKmh) {
                        Text("关闭").tag(0.0)
                        Text("25 公里/时").tag(25.0)
                        Text("30 公里/时").tag(30.0)
                        Text("35 公里/时").tag(35.0)
                        Text("40 公里/时").tag(40.0)
                    }
                } header: {
                    Text("检测")
                } footer: {
                    Text("长时间高速且速度几乎不变的骑行会标为「疑似电动车」，可一键排除。超速提醒在手动骑行时达到所选速度会震动警示。")
                }
                Section {
                    Picker("每周距离目标", selection: $weeklyGoalKm) {
                        Text("关闭").tag(0.0)
                        Text("20 公里").tag(20.0)
                        Text("30 公里").tag(30.0)
                        Text("50 公里").tag(50.0)
                        Text("100 公里").tag(100.0)
                    }
                } header: {
                    Text("目标")
                } footer: {
                    Text("设定后，首页会显示本周骑行距离的进度。仅本地统计，不含已排除记录。")
                }
                Section {
                    Toggle("步行", isOn: $recordWalking)
                    Toggle("电动车", isOn: $recordEBike)
                    Toggle("其他运动", isOn: $recordOther)
                } header: {
                    Text("自动记录的运动类型")
                } footer: {
                    Text("默认全部记录。关闭后，被动检测到的该类型运动不再自动保存。骑行与跑步始终记录；「电动车」指自动识别为疑似电动车的骑行。手动开始的骑行不受影响。")
                }
                externalSourcesSection

                Section("Apple 健康") {
                    Toggle("自动写回 Apple 健康", isOn: $healthWriteBack)
                    Button {
                        Task { await cleanupHealthDuplicates() }
                    } label: {
                        Text(isCleaningDuplicates ? String(localized: "正在清理...") : String(localized: "清理重复健康记录"))
                    }
                    .disabled(isCleaningDuplicates)
                    if let duplicateCleanupMessage {
                        Text(duplicateCleanupMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text("检测到新运动并准备写入时，系统才会请求写入权限；没有新记录时不会弹出。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("设置")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .sheet(isPresented: $showPaywall) { PaywallView() }
        }
    }

    /// 其他手表 / 运动 app 的记录：Garmin、华为、Zepp、Wahoo、Keep、Strava 都会写进 Apple 健康，
    /// 所以这里列的是「健康里有谁写过运动」，勾上谁就导谁，不需要逐家登录。
    @ViewBuilder
    private var externalSourcesSection: some View {
        Section {
            if externalImporter.sources.isEmpty {
                Button {
                    Task { await externalImporter.discoverSources() }
                } label: {
                    Text(externalImporter.isWorking
                         ? String(localized: "正在查找...")
                         : String(localized: "查找其他设备"))
                }
                .disabled(externalImporter.isWorking)
                if externalImporter.hasScanned && !externalImporter.isWorking {
                    Text("没有找到其他 app 写入的运动记录。若你的手表 app 已在往「健康」写数据，请到 健康 › 共享 › App 里允许「快乐轻骑」读取「体能训练」。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(externalImporter.sources) { discovered in
                    Toggle(isOn: binding(for: discovered.id)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(discovered.name)
                            Text("\(discovered.count) 条 · 最近 \(discovered.latest.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Button {
                    Task { await externalImporter.importEnabled() }
                } label: {
                    Text(externalImporter.isWorking
                         ? String(localized: "正在导入...")
                         : String(localized: "导入勾选的记录"))
                }
                .disabled(externalImporter.isWorking || enabledSourceIDs.isEmpty)
                Button("重新查找") {
                    Task { await externalImporter.discoverSources() }
                }
                .disabled(externalImporter.isWorking)
            }
            if let message = externalImporter.message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("其他手表与运动 App")
        } footer: {
            Text("Garmin Connect、华为运动健康、Zepp、Wahoo、Keep、Strava 等都会把运动写进 Apple 健康，勾选后即可导入，无需分别登录。导入的记录只读取不修改，删除本地记录不会影响对方的数据。")
        }
    }

    private func binding(for sourceID: String) -> Binding<Bool> {
        Binding(
            get: { enabledSourceIDs.contains(sourceID) },
            set: { isOn in
                ExternalSourcePreferences.setEnabled(isOn, for: sourceID)
                enabledSourceIDs = ExternalSourcePreferences.enabledSourceIDs
            }
        )
    }

    private func cleanupHealthDuplicates() async {
        isCleaningDuplicates = true
        duplicateCleanupMessage = nil
        let health = HealthService()
        guard await health.requestWriteAuthorization() else {
            duplicateCleanupMessage = String(localized: "需要先允许写入 Apple 健康。")
            isCleaningDuplicates = false
            return
        }
        let count = await health.cleanupDuplicateWorkouts()
        duplicateCleanupMessage = count == 0 ? String(localized: "没有发现本 app 写入的重复记录。") : String(localized: "已清理 \(count) 条重复记录。")
        isCleaningDuplicates = false
    }

    private var motionText: String {
        switch permissions.motionStatus {
        case .notDetermined: return String(localized: "未授权")
        case .restricted: return String(localized: "受限")
        case .denied: return String(localized: "已拒绝")
        case .authorized: return String(localized: "已授权")
        @unknown default: return String(localized: "未知")
        }
    }

    private var locationText: String {
        switch permissions.locationStatus {
        case .notDetermined: return String(localized: "未授权")
        case .restricted: return String(localized: "受限")
        case .denied: return String(localized: "已拒绝")
        case .authorizedWhenInUse: return String(localized: "使用期间")
        case .authorizedAlways: return String(localized: "始终")
        @unknown default: return String(localized: "未知")
        }
    }
}
