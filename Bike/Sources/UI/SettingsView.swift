import SwiftUI

/// 设置：权限状态 + 手动对账（M3 调试 / 演示用）。
struct SettingsView: View {
    @Environment(PermissionsManager.self) private var permissions
    @Environment(RideDetectionCoordinator.self) private var coordinator
    @Environment(\.dismiss) private var dismiss
    @AppStorage("healthWriteBack") private var healthWriteBack = true

    var body: some View {
        NavigationStack {
            Form {
                Section("权限") {
                    LabeledContent("运动与健身", value: motionText)
                    LabeledContent("定位", value: locationText)
                    Button("请求权限") { permissions.requestAll() }
                }
                Section("检测") {
                    Button("立即对账") {
                        Task { await coordinator.runReconciliation() }
                    }
                    if let last = coordinator.lastReconcileDate {
                        LabeledContent("上次对账", value: last.formatted(date: .omitted, time: .standard))
                    }
                    LabeledContent("本次会话已保存", value: "\(coordinator.savedRideCount)")
                }
                Section("Apple 健康") {
                    Toggle("自动写回 Apple 健康", isOn: $healthWriteBack)
                    Text("检测到的运动会写成 Apple 健康里的一次运动（含距离/卡路里/路线）。")
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
        }
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
