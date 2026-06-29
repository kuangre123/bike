import SwiftUI

/// 设置：权限状态 + 手动同步（M3 调试 / 演示用）。
struct SettingsView: View {
    @Environment(PermissionsManager.self) private var permissions
    @Environment(RideDetectionCoordinator.self) private var coordinator
    @Environment(\.dismiss) private var dismiss
    @AppStorage("healthWriteBack") private var healthWriteBack = true
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
                Section("检测") {
                    Button("同步运动数据") {
                        Task { await coordinator.runReconciliation() }
                    }
                    if let last = coordinator.lastReconcileDate {
                        LabeledContent("上次同步", value: last.formatted(date: .omitted, time: .standard))
                    }
                    LabeledContent("本次会话已保存", value: "\(coordinator.savedRideCount)")
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
