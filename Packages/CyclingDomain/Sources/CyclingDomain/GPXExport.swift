import Foundation

/// 把轨迹点导出为 GPX 1.1 文档（可导入 Strava 等）。纯函数，可单测。
/// 时间用 UTC ISO8601；有海拔才写 <ele>；经纬度 6 位小数，海拔 1 位。
public func gpxDocument(trackName: String, points: [GPSSample]) -> String {
    let iso = ISO8601DateFormatter()
    iso.timeZone = TimeZone(identifier: "UTC")

    func coord(_ v: Double) -> String { String(format: "%.6f", v) }
    func ele(_ v: Double) -> String { String(format: "%.1f", v) }

    var xml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <gpx version="1.1" creator="快乐轻骑" xmlns="http://www.topografix.com/GPX/1/1">
    <trk><name>\(xmlEscape(trackName))</name><trkseg>
    """
    for p in points {
        xml += "\n<trkpt lat=\"\(coord(p.latitude))\" lon=\"\(coord(p.longitude))\">"
        if let alt = p.altitude { xml += "<ele>\(ele(alt))</ele>" }
        xml += "<time>\(iso.string(from: p.timestamp))</time></trkpt>"
    }
    xml += "\n</trkseg></trk>\n</gpx>\n"
    return xml
}

/// XML 文本转义（用于 trackName 等自由文本）。
public func xmlEscape(_ s: String) -> String {
    s.replacingOccurrences(of: "&", with: "&amp;")
     .replacingOccurrences(of: "<", with: "&lt;")
     .replacingOccurrences(of: ">", with: "&gt;")
     .replacingOccurrences(of: "\"", with: "&quot;")
     .replacingOccurrences(of: "'", with: "&apos;")
}
