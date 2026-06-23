import Foundation

/// 路线功能的联网同意（默认关）。键 "routeNetworkEnabled"。
enum RoutePrefs {
    private static let key = "routeNetworkEnabled"

    static var networkEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}
