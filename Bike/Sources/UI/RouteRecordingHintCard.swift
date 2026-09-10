import SwiftUI

/// 「最近几次骑行没能记录路线」的首页提示。
///
/// 只在**这件事真的发生过几次**、且定位确实不是「始终」时出现（见 `RouteRecordingHint`）。
/// 不是一装上就催权限——那样对没遇到问题的人纯属骚扰。
struct RouteRecordingHintCard: View {
    let routelessCount: Int
    let onEnable: () -> Void
    let onDismiss: () -> Void

    @ViewBuilder
    private var actions: some View {
        Button("去设置", action: onEnable)
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(Color(red: 0.94, green: 0.48, blue: 0.22))
        Button("不再提示", action: onDismiss)
            .buttonStyle(.plain)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(
                    LinearGradient(
                        colors: [
                            Color(red: 0.98, green: 0.62, blue: 0.20),
                            Color(red: 0.96, green: 0.42, blue: 0.32)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 9) {
                Text("最近 \(routelessCount) 次骑行没能记录路线")
                    .font(.headline.weight(.heavy))
                    .fixedSize(horizontal: false, vertical: true)
                Text("定位权限改成「始终」，之后的骑行就会自动画出轨迹。已经记录的这几次补不回来。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                // 德语这两个词比中文长一倍多，并排在窄屏 iPhone 上会挤爆。
                // 文案已经挑短的了，布局这里再兜一层：放不下就竖排。
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { actions }
                    VStack(alignment: .leading, spacing: 8) { actions }
                }
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.82))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.85), lineWidth: 1)
        )
    }
}
