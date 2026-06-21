import SwiftUI

/// 未授权时的引导横幅 —— 真机上没有「始终」定位 + 运动权限，被动检测就静默失效。
struct PermissionBanner: View {
    let onEnable: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(
                    LinearGradient(
                        colors: [
                            Color(red: 0.04, green: 0.68, blue: 0.82),
                            Color(red: 0.36, green: 0.84, blue: 0.60)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 9) {
                Text("开启自动记录")
                    .font(.headline.weight(.heavy))
                Text("授予「始终」定位与运动权限后，快乐轻骑会在你运动时自动记录。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("开启权限", action: onEnable)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(Color(red: 0.04, green: 0.62, blue: 0.82))
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.82))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.85), lineWidth: 1)
        )
        .shadow(color: Color(red: 0.20, green: 0.70, blue: 0.80).opacity(0.12), radius: 14, y: 8)
    }
}
