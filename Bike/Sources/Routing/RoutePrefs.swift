import Foundation

/// 路线功能的联网同意（默认关）。键 "routeNetworkEnabled"。
enum RoutePrefs {
    private static let key = "routeNetworkEnabled"
    static let profileKey = "routeProfile"

    static var networkEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    /// 当前算路偏好对应的 BRouter 档名（默认 safety 安静）。RideNavigator 偏航重算时读它。
    static var profile: String {
        UserDefaults.standard.string(forKey: profileKey) ?? RoutePreference.safety.rawValue
    }
}

/// 用户的算路偏好。rawValue = BRouter 公共服务器的内置档名（实测均可用、路线确有区别）。
/// 注：「公园/草坪」级别的逐项权重需自定义算路档（公共服务器做不到），属后续/自建范畴。
enum RoutePreference: String, CaseIterable, Identifiable {
    case safety       // 安静少大车
    case river        // 沿河/水边，偏风景
    case trekking     // 通用均衡
    case shortest     // 最短直达

    var id: String { rawValue }

    var label: String {
        switch self {
        case .safety:   return "安静"
        case .river:    return "风景"
        case .trekking: return "通用"
        case .shortest: return "最短"
        }
    }

    var detail: String {
        switch self {
        case .safety:   return "避开车多的主干道，走住宅小路与自行车道"
        case .river:    return "尽量沿河边、水岸与绿道，风景更好（会绕远）"
        case .trekking: return "速度与安静均衡的通用骑行路线"
        case .shortest: return "尽量短、最直接，不挑路"
        }
    }

    var icon: String {
        switch self {
        case .safety:   return "leaf.fill"
        case .river:    return "water.waves"
        case .trekking: return "bicycle"
        case .shortest: return "arrow.right.to.line"
        }
    }
}
