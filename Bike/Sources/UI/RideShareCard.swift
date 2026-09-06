import SwiftUI
import UIKit
import CyclingDomain

/// 一次运动的分享卡片：地图底图 + 轨迹 + 核心数据 + 品牌落款。
/// `mapImage` 由 `RouteMapSnapshot` 预先渲染（轨迹已画在上面）；
/// 离线或无轨迹时为 nil，退回原来的纯色剪影，分享不会因此失败。
struct RideShareCard: View {
    let ride: RideModel
    var mapImage: UIImage?

    /// 卡片尺寸。底图按同样尺寸截取，1:1 铺满，不再二次缩放。
    static let size = CGSize(width: 360, height: 480)

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

            // 轨迹区：有底图时轨迹已画在底图上，这里只留出空间。
            ZStack {
                if mapImage == nil {
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
            .background(mapImage == nil ? Color.white.opacity(0.14) : Color.black.opacity(0.26))

            // 品牌落款（用地图底图时按 Apple 要求标注地图来源）
            ZStack {
                HStack(spacing: 6) {
                    Image(systemName: "bicycle")
                        .font(.caption.weight(.bold))
                    Text("快乐轻骑 · 自动记录每一次出行")
                        .font(.caption.weight(.semibold))
                }
                .frame(maxWidth: .infinity)

                if mapImage != nil {
                    HStack {
                        Spacer()
                        Text("地图 © Apple")
                            .font(.system(size: 8, weight: .medium))
                            .opacity(0.7)
                            .padding(.trailing, 10)
                    }
                }
            }
            .foregroundStyle(.white.opacity(0.8))
            .padding(.vertical, 12)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background {
            if let mapImage {
                ZStack {
                    Image(uiImage: mapImage)
                        .resizable()
                        .scaledToFill()
                    // 压暗上下两端，保证标题和数据行在任何底图上都读得清。
                    LinearGradient(
                        stops: [
                            .init(color: .black.opacity(0.62), location: 0),
                            .init(color: .black.opacity(0.12), location: 0.26),
                            .init(color: .black.opacity(0.14), location: 0.60),
                            .init(color: .black.opacity(0.70), location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .clipped()
            } else {
                LinearGradient(
                    colors: [
                        Color(red: 0.03, green: 0.55, blue: 0.76),
                        Color(red: 0.13, green: 0.72, blue: 0.58)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
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
    /// 先取地图底图（需要网络，可能耗时一两秒），失败则退回纯色剪影。
    @MainActor
    static func renderImage(for ride: RideModel) async -> UIImage? {
        let map = await RouteMapSnapshot.render(
            points: RideMapping.decodeRoute(ride.routeData),
            size: size,
            scale: 3
        )
        let renderer = ImageRenderer(content: RideShareCard(ride: ride, mapImage: map))
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
struct ShareableImage: Identifiable, Equatable {
    let id = UUID()
    let image: UIImage

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
}

/// UIActivityViewController 的 SwiftUI 包装（分享图片到微信/相册等）。
struct ShareImageSheet: UIViewControllerRepresentable {
    let image: UIImage

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [image], applicationActivities: nil)
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

/// 分享任意文件（如导出的 GPX）到其它 App。
struct ShareFileSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
