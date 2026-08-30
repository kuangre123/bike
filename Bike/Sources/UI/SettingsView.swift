import SwiftUI

/// 设置：权限状态 + 手动同步（M3 调试 / 演示用）。
struct SettingsView: View {
    @Environment(PermissionsManager.self) private var permissions
    @Environment(RideDetectionCoordinator.self) private var coordinator
    @Environment(\.dismiss) private var dismiss
    @AppStorage("healthWriteBack") private var healthWriteBack = true
    @AppStorage("ebikeAutoFlag") private var ebikeAutoFlag = true
    @AppStorage("overspeedAlertKmh") private var overspeedAlertKmh: Double = 0
    @AppStorage("recordWalking") private var recordWalking = true
    @AppStorage("recordEBike") private var recordEBike = true
    @AppStorage("recordOther") private var recordOther = true
    @State private var duplicateCleanupMessage: String?
    @State private var isCleaningDuplicates = false
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
                    Toggle("步行", isOn: $recordWalking)
                    Toggle("电动车", isOn: $recordEBike)
                    Toggle("其他运动", isOn: $recordOther)
                } header: {
                    Text("自动记录的运动类型")
                } footer: {
                    Text("默认全部记录。关闭后，被动检测到的该类型运动不再自动保存。骑行与跑步始终记录；「电动车」指自动识别为疑似电动车的骑行。手动开始的骑行不受影响。")
                }
                Section("Apple 健康") {
                    Toggle("自动写回 Apple 健康", isOn: $healthWriteBack)
                    Button(isCleaningDuplicates ? "正在清理..." : "清理重复健康记录") {
                        Task { await cleanupHealthDuplicates() }
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

    private func cleanupHealthDuplicates() async {
        isCleaningDuplicates = true
        duplicateCleanupMessage = nil
        let health = HealthService()
        guard await health.requestWriteAuthorization() else {
            duplicateCleanupMessage = "需要先允许写入 Apple 健康。"
            isCleaningDuplicates = false
            return
        }
        let count = await health.cleanupDuplicateWorkouts()
        duplicateCleanupMessage = count == 0 ? "没有发现本 app 写入的重复记录。" : "已清理 \(count) 条重复记录。"
        isCleaningDuplicates = false
    }

    private var motionText: String {
        switch permissions.motionStatus {
        case .notDetermined: return "未授权"
        case .restricted: return "受限"
        case .denied: return "已拒绝"
        case .authorized: return "已授权"
        @unknown default: return "未知"
        }
    }

    private var locationText: String {
        switch permissions.locationStatus {
        case .notDetermined: return "未授权"
        case .restricted: return "受限"
        case .denied: return "已拒绝"
        case .authorizedWhenInUse: return "使用期间"
        case .authorizedAlways: return "始终"
        @unknown default: return "未知"
        }
    }
}
