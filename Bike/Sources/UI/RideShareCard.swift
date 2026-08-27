import SwiftUI
import UIKit
import CyclingDomain

/// 一次运动的分享卡片：轨迹剪影 + 核心数据 + 品牌落款。
/// 轨迹用纯色剪影而非地图截图——无网络依赖、不暴露街道底图（隐私），观感也更干净。
struct RideShareCard: View {
    let ride: RideModel

    private var type: ActivityType { RideMapping.activityType(of: ride) }
    private var points: [RoutePointDTO] { RideMapping.decodeRoute(ride.routeData) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 头部：类型 + 日期
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Formatters.activityLabel(type))
                        .font(.system(size: 30, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    Text(Formatters.fullDateTime(ride.startDate))
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.white.opacity(0.85))
                }
                Spacer()
                Image(systemName: Formatters.activityIcon(type))
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.white.opacity(0.92))
            }
            .padding(24)

            // 轨迹剪影（无轨迹时用图标占位）
            ZStack {
                if points.count >= 2 {
                    RouteSilhouette(points: points)
                        .stroke(
                            .white,
                            style: StrokeStyle(lineWidth: 4.5, lineCap: .round, lineJoin: .round)
                        )
                        .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
                        .padding(28)
                } else {
                    Image(systemName: Formatters.activityIcon(type))
                        .font(.system(size: 88, weight: .bold))
                        .foregroundStyle(.white.opacity(0.30))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // 数据行
            HStack(spacing: 0) {
                metric(Formatters.distance(ride.distanceMeters), "距离")
                metric(Formatters.duration(ride.duration), "时长")
                metric(Formatters.speed(ride.avgSpeedMps), "均速")
                if let kcal = ride.calories {
                    metric(Formatters.calories(kcal), "消耗")
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .background(.white.opacity(0.14))

            // 品牌落款
            HStack(spacing: 6) {
                Image(systemName: "bicycle")
                    .font(.caption.weight(.bold))
                Text("快乐轻骑 · 自动记录每一次出行")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(.white.opacity(0.8))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        .frame(width: 360, height: 480)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.03, green: 0.55, blue: 0.76),
                    Color(red: 0.13, green: 0.72, blue: 0.58)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private func metric(_ value: String, _ title: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 17, weight: .heavy, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(title)
                .font(.caption2.weight(.medium))
                .opacity(0.8)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
    }

    /// 渲染成 3 倍分辨率图片（1080×1440），供系统分享。
    @MainActor
    static func renderImage(for ride: RideModel) -> UIImage? {
        let renderer = ImageRenderer(content: RideShareCard(ride: ride))
        renderer.scale = 3
        return renderer.uiImage
    }
}

/// 轨迹剪影 Shape：经纬度等比缩放并居中到画布（纬度翻转；经度按中纬度余弦校正横向比例）。
private struct RouteSilhouette: Shape {
    let points: [RoutePointDTO]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard points.count >= 2,
              let minLat = points.map(\.latitude).min(),
              let maxLat = points.map(\.latitude).max(),
              let minLon = points.map(\.longitude).min(),
              let maxLon = points.map(\.longitude).max() else { return path }

        let midLat = (minLat + maxLat) / 2
        let lonScale = cos(midLat * .pi / 180)   // 高纬度经度变「窄」
        let spanX = max((maxLon - minLon) * lonScale, 1e-6)
        let spanY = max(maxLat - minLat, 1e-6)
        let scale = min(rect.width / spanX, rect.height / spanY)
        let offsetX = (rect.width - spanX * scale) / 2
        let offsetY = (rect.height - spanY * scale) / 2

        func project(_ p: RoutePointDTO) -> CGPoint {
            CGPoint(
                x: rect.minX + offsetX + (p.longitude - minLon) * lonScale * scale,
                y: rect.minY + offsetY + (maxLat - p.latitude) * scale
            )
        }

        path.move(to: project(points[0]))
        for p in points.dropFirst() {
            path.addLine(to: project(p))
        }
        return path
    }
}

/// `.sheet(item:)` 用的可识别图片包装。
struct ShareableImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

/// UIActivityViewController 的 SwiftUI 包装（分享图片到微信/相册等）。
struct ShareImageSheet: UIViewControllerRepresentable {
    let image: UIImage

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [image], applicationActivities: nil)
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
