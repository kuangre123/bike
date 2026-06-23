import Foundation

/// 中国坐标系转换（WGS-84 ⇄ GCJ-02「火星坐标」）。
///
/// 背景：iOS 在中国大陆返回的 GPS 与 Apple 地图都是 GCJ-02；而 OSM/BRouter 用 WGS-84。
/// 直接把 GCJ 坐标发给 BRouter、或把 BRouter 的 WGS 路线画在 Apple 地图上，都会偏移几百米
/// （路线"穿楼穿路"）。中国境外两者一致，不转换。
public enum ChinaGeo {
    private static let a = 6378245.0                      // 克拉索夫斯基椭球长半轴
    private static let ee = 0.00669342162296594323        // 偏心率平方

    /// 粗略中国边界（含则可能在境内，需转换）。
    public static func isInsideChina(latitude: Double, longitude: Double) -> Bool {
        longitude >= 72.004 && longitude <= 137.8347 && latitude >= 0.8293 && latitude <= 55.8271
    }

    /// WGS-84 → GCJ-02（BRouter 路线 → 画在 Apple 地图）。
    public static func wgs84ToGcj02(_ c: GeoCoordinate) -> GeoCoordinate {
        guard isInsideChina(latitude: c.latitude, longitude: c.longitude) else { return c }
        let (dLat, dLon) = offset(lat: c.latitude, lon: c.longitude)
        return GeoCoordinate(latitude: c.latitude + dLat, longitude: c.longitude + dLon)
    }

    /// GCJ-02 → WGS-84（Apple 定位/目的地 → 发给 BRouter）。用「两倍减」粗逆，误差约 1 米。
    public static func gcj02ToWgs84(_ c: GeoCoordinate) -> GeoCoordinate {
        guard isInsideChina(latitude: c.latitude, longitude: c.longitude) else { return c }
        let g = wgs84ToGcj02(c)
        return GeoCoordinate(latitude: c.latitude * 2 - g.latitude, longitude: c.longitude * 2 - g.longitude)
    }

    /// 给定 WGS 点，计算到 GCJ 的经纬度偏移量。
    private static func offset(lat: Double, lon: Double) -> (dLat: Double, dLon: Double) {
        var dLat = transformLat(x: lon - 105, y: lat - 35)
        var dLon = transformLon(x: lon - 105, y: lat - 35)
        let radLat = lat / 180 * .pi
        var magic = sin(radLat)
        magic = 1 - ee * magic * magic
        let sqrtMagic = magic.squareRoot()
        dLat = (dLat * 180) / ((a * (1 - ee)) / (magic * sqrtMagic) * .pi)
        dLon = (dLon * 180) / (a / sqrtMagic * cos(radLat) * .pi)
        return (dLat, dLon)
    }

    private static func transformLat(x: Double, y: Double) -> Double {
        var ret = -100 + 2 * x + 3 * y + 0.2 * y * y + 0.1 * x * y + 0.2 * abs(x).squareRoot()
        ret += (20 * sin(6 * x * .pi) + 20 * sin(2 * x * .pi)) * 2 / 3
        ret += (20 * sin(y * .pi) + 40 * sin(y / 3 * .pi)) * 2 / 3
        ret += (160 * sin(y / 12 * .pi) + 320 * sin(y * .pi / 30)) * 2 / 3
        return ret
    }

    private static func transformLon(x: Double, y: Double) -> Double {
        var ret = 300 + x + 2 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * abs(x).squareRoot()
        ret += (20 * sin(6 * x * .pi) + 20 * sin(2 * x * .pi)) * 2 / 3
        ret += (20 * sin(x * .pi) + 40 * sin(x / 3 * .pi)) * 2 / 3
        ret += (150 * sin(x / 12 * .pi) + 300 * sin(x / 30 * .pi)) * 2 / 3
        return ret
    }
}
