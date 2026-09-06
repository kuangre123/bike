import Foundation
import MapKit
import UIKit

/// 把一段轨迹渲染成「Apple 地图底图 + 轨迹线」的整张图，给分享卡片当背景。
///
/// 需要下载地图瓦片，因此是异步的；离线或取景失败时返回 nil，
/// 卡片会自动退回原来的纯色剪影，分享不会因此失败。
enum RouteMapSnapshot {
    /// 轨迹在成图里的安全区：上下留白留给卡片的标题栏和数据行，避免轨迹被文字压住。
    private static let insets = UIEdgeInsets(top: 118, left: 34, bottom: 150, right: 34)

    /// 最小取景跨度。几十米的短途若按实际范围取景，地图会放大到只剩一个路口、看不出在哪。
    private static let minimumSpanMeters: Double = 400

    private static let routeColor = UIColor(red: 0.02, green: 0.44, blue: 0.66, alpha: 1)
    private static let startColor = UIColor(red: 0.13, green: 0.72, blue: 0.58, alpha: 1)
    private static let endColor = UIColor(red: 0.95, green: 0.35, blue: 0.30, alpha: 1)

    /// 渲染 `size`（点）× `scale` 倍的底图。轨迹不足两点时返回 nil。
    static func render(points: [RoutePointDTO], size: CGSize, scale: CGFloat) async -> UIImage? {
        guard points.count >= 2 else { return nil }
        let coordinates = points.map {
            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
        }
        guard let rect = mapRect(fitting: coordinates, into: size) else { return nil }

        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(rect)
        options.size = size
        options.scale = scale
        // 卡片自带深色压暗层，底图固定用浅色（跟随系统深色会和压暗层叠成一片黑）。
        options.traitCollection = UITraitCollection(userInterfaceStyle: .light)
        let configuration = MKStandardMapConfiguration(emphasisStyle: .muted)
        configuration.pointOfInterestFilter = .excludingAll
        options.preferredConfiguration = configuration

        let snapshotter = MKMapSnapshotter(options: options)
        return await withCheckedContinuation { continuation in
            snapshotter.start(with: .global(qos: .userInitiated)) { snapshot, _ in
                guard let snapshot else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(
                    returning: draw(coordinates, on: snapshot, size: size, scale: scale)
                )
            }
        }
    }

    /// 反推取景框：先把轨迹外接框撑到最小跨度，再算出「一个点等于多少地图单位」，
    /// 使轨迹正好落进安全区，最后按整图尺寸把取景框放大回去。
    private static func mapRect(
        fitting coordinates: [CLLocationCoordinate2D],
        into size: CGSize
    ) -> MKMapRect? {
        var bounds = MKMapRect.null
        for coordinate in coordinates {
            let point = MKMapPoint(coordinate)
            bounds = bounds.union(MKMapRect(x: point.x, y: point.y, width: 0, height: 0))
        }
        guard !bounds.isNull else { return nil }

        let midLatitude = MKMapPoint(x: bounds.midX, y: bounds.midY).coordinate.latitude
        let minimumSide = minimumSpanMeters * MKMapPointsPerMeterAtLatitude(midLatitude)
        if bounds.width < minimumSide || bounds.height < minimumSide {
            let width = max(bounds.width, minimumSide)
            let height = max(bounds.height, minimumSide)
            bounds = MKMapRect(
                x: bounds.midX - width / 2,
                y: bounds.midY - height / 2,
                width: width,
                height: height
            )
        }

        let inner = CGSize(
            width: size.width - insets.left - insets.right,
            height: size.height - insets.top - insets.bottom
        )
        guard inner.width > 0, inner.height > 0 else { return nil }

        let unitsPerPoint = max(bounds.width / inner.width, bounds.height / inner.height)
        let innerCenter = CGPoint(
            x: insets.left + inner.width / 2,
            y: insets.top + inner.height / 2
        )
        return MKMapRect(
            x: bounds.midX - innerCenter.x * unitsPerPoint,
            y: bounds.midY - innerCenter.y * unitsPerPoint,
            width: size.width * unitsPerPoint,
            height: size.height * unitsPerPoint
        )
    }

    private static func draw(
        _ coordinates: [CLLocationCoordinate2D],
        on snapshot: MKMapSnapshotter.Snapshot,
        size: CGSize,
        scale: CGFloat
    ) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            snapshot.image.draw(at: .zero)

            let cg = context.cgContext
            cg.setLineCap(.round)
            cg.setLineJoin(.round)

            let path = CGMutablePath()
            path.addLines(between: coordinates.map { snapshot.point(for: $0) })

            // 白色描边打底、深色主线在上：浅色路面和深色屋顶上都看得清。
            cg.addPath(path)
            cg.setStrokeColor(UIColor.white.withAlphaComponent(0.92).cgColor)
            cg.setLineWidth(9)
            cg.strokePath()

            cg.addPath(path)
            cg.setStrokeColor(routeColor.cgColor)
            cg.setLineWidth(5)
            cg.strokePath()

            if let first = coordinates.first, let last = coordinates.last {
                marker(cg, at: snapshot.point(for: first), fill: startColor)
                marker(cg, at: snapshot.point(for: last), fill: endColor)
            }
        }
    }

    private static func marker(_ cg: CGContext, at point: CGPoint, fill: UIColor) {
        let outer = CGRect(x: point.x - 7, y: point.y - 7, width: 14, height: 14)
        cg.setFillColor(UIColor.white.cgColor)
        cg.fillEllipse(in: outer)
        cg.setFillColor(fill.cgColor)
        cg.fillEllipse(in: outer.insetBy(dx: 3.5, dy: 3.5))
    }
}
