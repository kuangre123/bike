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
///
/// 分两组，因为它们不是同一维度的东西：「公路车」是车型，「安静」是风格，
/// 不是互相的替代项。但 BRouter 一次只吃一个档名，所以只能并成一个列表、在 UI 里分组。
///
/// 注：「公园/草坪」级别的逐项权重需自定义算路档（公共服务器做不到），属后续/自建范畴。
enum RoutePreference: String, CaseIterable, Identifiable {
    // MARK: 车型
    case fastbike     // 公路车：偏快、吃铺装路
    case gravel       // Gravel：铺装与土路都能走
    case mtb          // 山地车：不回避土路与非铺装

    // MARK: 风格
    case safety       // 安静少大车
    case river        // 沿河/水边，偏风景
    case trekking     // 通用均衡
    case shortest     // 最短直达

    var id: String { rawValue }

    enum Group: String, CaseIterable, Identifiable {
        case bikeType, style
        var id: String { rawValue }
        var label: String {
            switch self {
            case .bikeType: return String(localized: "车型")
            case .style:    return String(localized: "风格")
            }
        }
    }

    var group: Group {
        switch self {
        case .fastbike, .gravel, .mtb: return .bikeType
        case .safety, .river, .trekking, .shortest: return .style
        }
    }

    static func all(in group: Group) -> [RoutePreference] {
        allCases.filter { $0.group == group }
    }

    var label: String {
        switch self {
        case .fastbike: return String(localized: "公路车")
        case .gravel:   return String(localized: "Gravel")
        case .mtb:      return String(localized: "山地车")
        case .safety:   return String(localized: "安静")
        case .river:    return String(localized: "风景")
        case .trekking: return String(localized: "通用")
        case .shortest: return String(localized: "最短")
        }
    }

    var detail: String {
        switch self {
        case .fastbike: return String(localized: "偏快、优先铺装路面，避开土路与台阶")
        case .gravel:   return String(localized: "铺装与碎石土路都走，偏离主干道")
        case .mtb:      return String(localized: "不回避土路与非铺装路面，可走林道")
        case .safety:   return String(localized: "避开车多的主干道，走住宅小路与自行车道")
        case .river:    return String(localized: "尽量沿河边、水岸与绿道，风景更好（会绕远）")
        case .trekking: return String(localized: "速度与安静均衡的通用骑行路线")
        case .shortest: return String(localized: "尽量短、最直接，不挑路")
        }
    }

    var icon: String {
        switch self {
        case .fastbike: return "bolt.fill"
        case .gravel:   return "road.lanes"
        case .mtb:      return "mountain.2.fill"
        case .safety:   return "leaf.fill"
        case .river:    return "water.waves"
        case .trekking: return "bicycle"
        case .shortest: return "arrow.right.to.line"
        }
    }
}
