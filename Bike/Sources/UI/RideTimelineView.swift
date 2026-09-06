import SwiftUI
import SwiftData
import UIKit
import MapKit
import CoreLocation
import Combine
import StoreKit
import CyclingDomain

/// 运动时间线：权限引导 + 本周概览 + 按自然日分组；点进单次看详情，滑动删除。
struct RideTimelineView: View {
    @Environment(\.modelContext) private var context
    @Environment(PermissionsManager.self) private var permissions
    @Environment(RideDetectionCoordinator.self) private var coordinator
    @Environment(\.openURL) private var openURL
    @Environment(\.requestReview) private var requestReview
    @Query(sort: \RideModel.startDate, order: .reverse) private var rides: [RideModel]
    @State private var showingSettings = false
    @State private var showingManualRide = false
    @State private var showingExcluded = false
    @State private var showingAdvancedStats = false
    @State private var showingHeatmap = false
    @State private var showPaywall = false
    /// 手动记录被同时段的已有手动记录挡下时提示用户，避免「点了保存却什么都没发生」。
    @State private var manualSaveBlocked = false
    @StateObject private var subscription = SubscriptionManager.shared
    @AppStorage("weeklyGoalKm") private var weeklyGoalKm: Double = 30
    @State private var path = NavigationPath()

    /// 计入统计与主列表的记录（排除「已排除（电动车）」）。
    private var activeRides: [RideModel] { rides.filter { !$0.excludedAsEBike } }
    private var excludedRides: [RideModel] { rides.filter(\.excludedAsEBike) }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                FreshHomeBackground()
                    .ignoresSafeArea()

                List {
                    Section {
                        HomeHeroCard(rides: activeRides) {
                            showingManualRide = true
                        }
                    }
                    .clearHomeRow()

                    if permissions.needsSetup {
                        Section {
                            PermissionBanner(onEnable: enablePermissions)
                        }
                        .clearHomeRow()
                    }

                    if rides.isEmpty {
                        Section {
                            EmptyRideCard()
                        }
                        .clearHomeRow()
                    } else {
                        Section {
                            if weeklyGoalKm > 0 {
                                WeeklyGoalCard(rides: activeRides, goalKm: weeklyGoalKm)
                            }
                            StatsSummaryView(rides: activeRides)
                            Button(action: openAdvancedStats) {
                                HStack(spacing: 10) {
                                    Image(systemName: "chart.bar.xaxis")
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(.white)
                                        .frame(width: 30, height: 30)
                                        .background(
                                            LinearGradient(colors: [Color(red: 0.04, green: 0.68, blue: 0.82),
                                                                    Color(red: 0.27, green: 0.82, blue: 0.62)],
                                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                                        )
                                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text("高级统计").font(.subheadline.weight(.heavy)).foregroundStyle(.primary)
                                        Text("记录 · 连续天数 · 月度趋势").font(.caption2).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if !subscription.isPro {
                                        Text("Pro").font(.caption2.weight(.heavy)).foregroundStyle(.white)
                                            .padding(.horizontal, 7).padding(.vertical, 3)
                                            .background(Color.orange).clipShape(Capsule())
                                    }
                                    Image(systemName: "chevron.right").font(.caption.weight(.bold))
                                        .foregroundStyle(.secondary.opacity(0.55))
                                }
                                .padding(12)
                                .background(Color.white.opacity(0.82))
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.white.opacity(0.85), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 8)
                        } header: {
                            HomeSectionHeader(String(localized: "本周节奏"))
                        }
                        .clearHomeRow()

                        ForEach(groupedByDay, id: \.day) { group in
                            Section {
                                ForEach(group.rides) { ride in
                                    Button {
                                        path.append(ride)
                                    } label: {
                                        RideRowView(ride: ride)
                                    }
                                    .buttonStyle(.plain)
                                    .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                                    .swipeActions(edge: .trailing) {
                                        Button("删除", role: .destructive) {
                                            Task { await deleteRide(ride) }
                                        }
                                        if RideMapping.activityType(of: ride) == .cycling {
                                            Button("标为电动车") {
                                                Task { await EBikeFlagging.exclude(ride, context: context) }
                                            }
                                            .tint(.orange)
                                        }
                                    }
                                    .contextMenu {
                                        if let candidate = mergeCandidate(for: ride) {
                                            Button {
                                                Task { await RideMerging.merge(candidate, ride, context: context) }
                                            } label: {
                                                Label("与 \(Formatters.clockTime(candidate.startDate)) 的记录合并",
                                                      systemImage: "arrow.triangle.merge")
                                            }
                                        }
                                    }
                                }
                            } header: {
                                HomeSectionHeader(group.day)
                            }
                            .textCase(nil)
                        }

                        if !excludedRides.isEmpty {
                            Section {
                                DisclosureGroup(isExpanded: $showingExcluded) {
                                    ForEach(excludedRides) { ride in
                                        Button {
                                            path.append(ride)
                                        } label: {
                                            RideRowView(ride: ride)
                                                .opacity(0.45)
                                                .saturation(0.3)
                                        }
                                        .buttonStyle(.plain)
                                        .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                                        .listRowBackground(Color.clear)
                                        .listRowSeparator(.hidden)
                                        .swipeActions(edge: .trailing) {
                                            Button("删除", role: .destructive) {
                                                Task { await deleteRide(ride) }
                                            }
                                            Button("恢复") {
                                                Task { await EBikeFlagging.restore(ride, context: context) }
                                            }
                                            .tint(.green)
                                        }
                                    }
                                } label: {
                                    Label("已排除（电动车） \(excludedRides.count) 条", systemImage: "bolt.slash")
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(.secondary)
                                }
                                .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                            }
                            .textCase(nil)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("快乐轻骑")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .navigationDestination(for: RideModel.self) { ride in
                RideDetailView(ride: ride)
            }
            .navigationDestination(isPresented: $showingAdvancedStats) {
                AdvancedStatsView(rides: rides)
            }
            .navigationDestination(isPresented: $showingHeatmap) {
                RouteHeatmapView(rides: rides)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingHeatmap = true
                    } label: {
                        Label("骑行足迹", systemImage: "map")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Label("设置", systemImage: "gearshape")
                    }
                }
                #if DEBUG
                if ProcessInfo.processInfo.environment["SHOW_SAMPLE_BUTTON"] == "1" {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("示例", systemImage: "plus", action: addSamples)
                    }
                }
                #endif
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
            .fullScreenCover(isPresented: $showingManualRide) {
                ManualRideView(onSave: saveManualRide)
            }
            .alert("未保存", isPresented: $manualSaveBlocked) {
                Button("好") {}
            } message: {
                Text("这段时间已有一条你手动记录的运动，为避免重复没有再存一次。")
            }
            .task { PhoneWatchSync.shared.send(todaySummary) }
            .task {
                // 价值时刻①：打开时间线看到自动记录的成果（被动用户的主场景）。
                // 延迟让 UI 稳定，避免启动瞬间打断；门槛全在 ReviewPrompt 里。
                try? await Task.sleep(for: .seconds(2))
                if ReviewPrompt.registerPositiveMomentAndDecide(totalRides: activeRides.count) {
                    requestReview()
                }
            }
            .onChange(of: activeRides.count) { PhoneWatchSync.shared.send(todaySummary) }
            .onAppear {
                permissions.refresh()
                #if DEBUG
                if ProcessInfo.processInfo.environment["SEED_SAMPLE"] == "1", rides.isEmpty {
                    addSamples()
                }
                if ProcessInfo.processInfo.environment["OPEN_FIRST_DETAIL"] == "1",
                   path.isEmpty, let first = rides.first(where: { $0.routeData != nil }) ?? rides.first {
                    path.append(first)
                }
                #endif
            }
        }
    }

    private func saveManualRide(_ ride: Ride) {
        let store = RideStore(context: context)
        let result = (try? store.save([ride], autoDetected: false)) ?? .empty
        guard let model = result.inserted.first else {
            manualSaveBlocked = true
            return
        }
        let replacedHealthUUIDs = result.replacedHealthWorkoutUUIDs

        // 价值时刻②：刚完成并保存一次手动骑行。延迟等全屏页收起再弹。
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            if ReviewPrompt.registerPositiveMomentAndDecide(totalRides: activeRides.count) {
                requestReview()
            }
        }

        let writeBack = UserDefaults.standard.object(forKey: "healthWriteBack") as? Bool ?? true

        Task { @MainActor in
            let health = HealthService()
            // 被本次实录替换掉的自动记录（如骑行途中被动检测的估算记录）：
            // 一并删掉它写进 Apple 健康的 workout，避免残留错误数据。
            if !replacedHealthUUIDs.isEmpty, await health.requestWriteAuthorization() {
                for uuid in replacedHealthUUIDs {
                    _ = await health.deleteWorkout(uuid: uuid)
                }
            }
            guard writeBack else { return }
            guard await health.requestWriteAuthorization() else { return }
            let route = RideMapping.decodeRoute(model.routeData)
            let workoutEnd = model.startDate.addingTimeInterval(model.duration)
            if let uuid = await health.saveWorkout(
                activityType: RideMapping.activityType(of: model),
                start: model.startDate,
                end: workoutEnd,
                calories: model.calories,
                distanceMeters: model.distanceMeters,
                avgSpeedMps: model.avgSpeedMps,
                route: route
            ) {
                model.healthKitWorkoutUUID = uuid
                try? context.save()
            }
        }
    }

    /// 合并候选：时间上紧邻的前一条（同类型、间隔 ≤ 2 小时才给入口）。
    private func mergeCandidate(for ride: RideModel) -> RideModel? {
        // activeRides 沿用 @Query 的开始时间倒序，first 即最近的更早一条
        guard let previous = activeRides.first(where: { $0.startDate < ride.startDate }) else { return nil }
        return RideMerging.canMerge(previous, ride) ? previous : nil
    }

    /// 高级统计：Pro 专享。未订阅先弹 paywall。
    private func openAdvancedStats() {
        if subscription.isPro {
            showingAdvancedStats = true
        } else {
            showPaywall = true
        }
    }

    private func deleteRide(_ ride: RideModel) async {
        if let uuid = ride.healthKitWorkoutUUID {
            let health = HealthService()
            _ = await health.requestWriteAuthorization()
            _ = await health.deleteWorkout(uuid: uuid)
        }
        context.delete(ride)
        try? context.save()
    }

    /// 已拒绝 → 跳系统设置；未决定 → 直接弹系统授权。
    private func enablePermissions() {
        let denied: [CLAuthorizationStatus] = [.denied, .restricted]
        if denied.contains(permissions.locationStatus)
            || permissions.motionStatus == .denied || permissions.motionStatus == .restricted {
            openURL(URL(string: UIApplication.openSettingsURLString)!)
        } else {
            coordinator.enableDetection()
        }
    }

    /// 今日概览（同步给手表）；已排除的电动车记录不计入。
    private var todaySummary: WatchDaySummary {
        let today = activeRides.filter { Calendar.current.isDateInToday($0.startDate) }
        return WatchDaySummary(
            count: today.count,
            durationSeconds: today.reduce(0) { $0 + $1.duration },
            distanceMeters: today.reduce(0) { $0 + ($1.distanceMeters ?? 0) }
        )
    }

    /// 按自然日分组（不含已排除）；日组按日期倒序，组内沿用 @Query 的开始时间倒序。
    private var groupedByDay: [(day: String, rides: [RideModel])] {
        let cal = Calendar.current
        let groups = Dictionary(grouping: activeRides) { cal.startOfDay(for: $0.startDate) }
        return groups
            .sorted { $0.key > $1.key }
            .map { (day: Formatters.dayHeader($0.key), rides: $0.value) }
    }

    #if DEBUG
    private func addSamples() {
        let store = RideStore(context: context)
        _ = try? store.save(SampleData.rides(), autoDetected: false)
    }
    #endif
}

private struct FreshHomeBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(red: 0.83, green: 0.97, blue: 1.00),
                Color(red: 0.93, green: 1.00, blue: 0.95),
                Color(red: 1.00, green: 0.99, blue: 0.90)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

private struct HomeHeroCard: View {
    let rides: [RideModel]
    let onStartRide: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("快乐轻骑")
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    Text(heroSubtitle)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                Image(systemName: "bicycle")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 58, height: 58)
                    .background(
                        LinearGradient(
                            colors: [
                                Color(red: 0.04, green: 0.68, blue: 0.82),
                                Color(red: 0.27, green: 0.82, blue: 0.62)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            HStack(spacing: 8) {
                heroMetric("今日", Formatters.duration(todayDuration), "sun.max.fill", .orange)
                heroMetric("本周", "\(weekRides.count) 次", "sparkles", .mint)
                heroMetric("距离", totalDistanceText, "location.fill", .cyan)
            }

            Button(action: onStartRide) {
                Label("开始骑行", systemImage: "play.fill")
                    .font(.headline.weight(.heavy))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        LinearGradient(
                            colors: [
                                Color(red: 0.04, green: 0.68, blue: 0.82),
                                Color(red: 0.22, green: 0.82, blue: 0.60)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [
                    Color.white.opacity(0.93),
                    Color(red: 0.90, green: 1.00, blue: 0.98).opacity(0.88)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.9), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .shadow(color: Color(red: 0.20, green: 0.70, blue: 0.80).opacity(0.16), radius: 18, y: 10)
    }

    private var heroSubtitle: String {
        if todayRides.isEmpty { return String(localized: "今天还很清爽，适合出门动一动") }
        return String(localized: "今天已记录 \(todayRides.count) 次运动")
    }

    private var todayRides: [RideModel] {
        rides.filter { Calendar.current.isDateInToday($0.startDate) }
    }

    private var weekRides: [RideModel] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        return rides.filter { $0.startDate >= cutoff }
    }

    private var todayDuration: TimeInterval {
        todayRides.reduce(0) { $0 + $1.duration }
    }

    private var totalDistanceText: String {
        let meters = weekRides.reduce(0.0) { $0 + ($1.distanceMeters ?? 0) }
        return Formatters.distance(meters)
    }

    private func heroMetric(_ title: String, _ value: String, _ icon: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: icon)
                .font(.caption.weight(.bold))
                .foregroundStyle(color)
                .frame(width: 24, height: 24)
                .background(color.opacity(0.13))
                .clipShape(Circle())
            Text(value)
                .font(.headline.weight(.heavy))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.white.opacity(0.58))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct EmptyRideCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "wind")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(Color(red: 0.04, green: 0.68, blue: 0.82))
                .frame(width: 54, height: 54)
                .background(Color.white.opacity(0.74))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text("还没有运动记录")
                    .font(.title3.weight(.bold))
                Text("第一段轻松出行会出现在这里。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color.white.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.88), lineWidth: 1)
        )
    }
}

private struct HomeSectionHeader: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(Color(red: 0.10, green: 0.34, blue: 0.40))
            .padding(.leading, 2)
            .textCase(nil)
    }
}

private extension View {
    func clearHomeRow() -> some View {
        self
            .listRowInsets(EdgeInsets(top: 7, leading: 16, bottom: 7, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .textCase(nil)
    }
}

@MainActor
private final class ManualRideSession: NSObject, ObservableObject, CLLocationManagerDelegate {
    enum HeartRateState: Equatable {
        case requestingAuthorization
        case waitingForData
        case unavailable
        case live(Double)
        case recent(Double)

        var displayText: String {
            switch self {
            case .requestingAuthorization:
                return String(localized: "等待授权")
            case .waitingForData:
                return String(localized: "等待心率")
            case .unavailable:
                return String(localized: "健康不可用")
            case .live(let bpm), .recent(let bpm):
                return String(localized: "\(Int(bpm.rounded())) 次/分钟")
            }
        }

        var title: String {
            if case .recent = self { return String(localized: "最近心率") }
            return String(localized: "心率")
        }
    }

    @Published private(set) var startDate = Date()
    @Published private(set) var samples: [GPSSample] = []
    @Published private(set) var distanceMeters: Double = 0
    @Published private(set) var displayLocation: GPSSample?
    @Published private(set) var currentHeartRate: Double?
    @Published private(set) var averageHeartRate: Double?
    @Published private(set) var heartRateState: HeartRateState = .requestingAuthorization
    @Published private(set) var isPaused = false
    /// 停等自动暂停（等红灯不计时长）：GPS 持续采集以便检测恢复移动，仅计时冻结。
    @Published private(set) var isAutoPaused = false

    private let locationManager = CLLocationManager()
    private let health = HealthService()
    private var heartRateTask: Task<Void, Never>?
    /// 当前采信的心率读数（手表实时推送与 HealthKit 轮询里测量时间更新的那条）。
    private var latestHeartRate: WatchHeartRate?
    private var lastAcceptedLocation: CLLocation?
    private var lastOverspeedAlert: Date?

    /// 有效计时 + 停等判定（纯逻辑，见 CyclingDomain.ActiveTimeTracker，有单测覆盖）。
    private var tracker = ActiveTimeTracker()

    private let maximumHorizontalAccuracy: CLLocationAccuracy = 25
    private let minimumSegmentDistance: CLLocationDistance = 10
    private let minimumMovingSpeed: CLLocationSpeed = 1.4

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.activityType = .fitness
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
        // 码表开着时按最高频率送定位：距离过滤会让人停住后彻底收不到回调，
        // 速度读数卡死，停等也判不出来（GPS 芯片本来就已按 Best 精度全速运行）。
        locationManager.distanceFilter = kCLDistanceFilterNone
    }

    var duration: TimeInterval {
        tracker.activeDuration(at: Date())
    }

    var averageSpeedMps: Double {
        CyclingDomain.averageSpeedMps(distanceMeters: distanceMeters, duration: duration)
    }

    /// 当前时速（km/h），码表显示用。
    var currentSpeedKmh: Double {
        max(0, displayLocation?.speedMps ?? 0) * 3.6
    }

    var coordinates: [CLLocationCoordinate2D] {
        routeSamples.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }

    var currentCoordinate: CLLocationCoordinate2D? {
        displayLocation.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }

    var isRecordingRoute: Bool {
        !samples.isEmpty
    }

    private var routeSamples: [GPSSample] {
        if !samples.isEmpty { return samples }
        if let displayLocation { return [displayLocation] }
        return []
    }

    func start() {
        startDate = Date()
        samples = []
        distanceMeters = 0
        displayLocation = nil
        lastAcceptedLocation = nil
        currentHeartRate = nil
        averageHeartRate = nil
        latestHeartRate = nil
        heartRateState = .requestingAuthorization
        lastOverspeedAlert = nil
        tracker.start(at: startDate)
        syncPauseFlags()
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
        startHeartRatePolling()
    }

    /// UI 每秒心跳：停住不动时 iOS 往往不再回调定位，只靠定位驱动判不出这次停等，
    /// 等红灯会被整段算进骑行时长。
    func tick() {
        let now = Date()
        tracker.tick(at: now, armed: !samples.isEmpty)
        syncPauseFlags()
        // 手表推来的心率走实时通道，每秒取一次；HealthKit 轮询 10 秒才一轮，且要等
        // 手表后台回写，慢几十秒到几分钟。
        applyHeartRate(PhoneWatchSync.shared.watchHeartRate, at: now)
    }

    func pause() {
        guard !isPaused else { return }
        tracker.manualPause(at: Date())
        syncPauseFlags()
        lastAcceptedLocation = nil
        locationManager.stopUpdatingLocation()
    }

    func resume() {
        guard isPaused else { return }
        tracker.manualResume(at: Date())
        syncPauseFlags()
        lastAcceptedLocation = nil
        locationManager.startUpdatingLocation()
    }

    private func syncPauseFlags() {
        if isPaused != tracker.isManuallyPaused { isPaused = tracker.isManuallyPaused }
        if isAutoPaused != tracker.isAutoPaused { isAutoPaused = tracker.isAutoPaused }
    }

    func stop() -> Ride? {
        locationManager.stopUpdatingLocation()
        heartRateTask?.cancel()
        heartRateTask = nil
        lastAcceptedLocation = nil

        let end = Date()
        let duration = tracker.activeDuration(at: end)
        guard duration >= RideDetectionPolicy.minimumRideDuration else { return nil }

        let distance = distanceMeters
        let speed = CyclingDomain.averageSpeedMps(distanceMeters: distance, duration: duration)
        return Ride(
            activityType: .cycling,
            start: startDate,
            end: end,
            source: .gpsTracked,
            distanceMeters: distance > 0 ? distance : nil,
            avgSpeedMps: speed > 0 ? speed : nil,
            calories: estimateCalories(for: .cycling, avgSpeedMps: speed, duration: duration),
            confidence: 2,
            avgHeartRate: averageHeartRate,
            activeDuration: duration,
            route: samples.isEmpty ? nil : samples
        )
    }

    func discard() {
        locationManager.stopUpdatingLocation()
        heartRateTask?.cancel()
        heartRateTask = nil
        lastAcceptedLocation = nil
    }

    /// 超速提醒：达到设置阈值（0=关闭）触发警示震动，10 秒内不重复。
    private func checkOverspeed(_ location: CLLocation) {
        let thresholdKmh = UserDefaults.standard.double(forKey: "overspeedAlertKmh")
        guard thresholdKmh > 0, location.speed >= 0, location.speed * 3.6 >= thresholdKmh else { return }
        let now = Date()
        if let last = lastOverspeedAlert, now.timeIntervalSince(last) < 10 { return }
        lastOverspeedAlert = now
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor [weak self, locations] in
            self?.handleLocations(locations)
        }
    }

    private func handleLocations(_ locations: [CLLocation]) {
        guard !isPaused else { return }
        for location in locations where location.horizontalAccuracy >= 0 {
            displayLocation = sample(from: location)
            // 只传 GPS 报速，不用位移推算兜底：静止时 GPS 抖动能推出好几 m/s 的假速度，
            // 停等就永远判不出来。报速无效交给 tick() 的断流兜底冻结。
            tracker.ingestLocation(
                timestamp: location.timestamp,
                speedMps: location.speed,
                armed: !samples.isEmpty
            )
            syncPauseFlags()
            checkOverspeed(location)

            // 自动暂停中：不累计距离/轨迹，但记住位置，恢复后从这里继续（跳变不计入距离）。
            if isAutoPaused {
                lastAcceptedLocation = location
                continue
            }

            guard location.horizontalAccuracy <= maximumHorizontalAccuracy else { continue }
            guard tracker.isRunning else { continue }
            guard tracker.isWarmedUp(at: location.timestamp) else { continue }

            if let last = lastAcceptedLocation {
                let segmentDistance = location.distance(from: last)
                let elapsed = location.timestamp.timeIntervalSince(last.timestamp)
                let derivedSpeed = elapsed > 0 ? segmentDistance / elapsed : 0
                let reportedSpeed = max(0, location.speed)
                let movingSpeed = max(reportedSpeed, derivedSpeed)

                guard segmentDistance >= minimumSegmentDistance || movingSpeed >= minimumMovingSpeed else {
                    lastAcceptedLocation = location
                    continue
                }

                distanceMeters += segmentDistance
                if samples.isEmpty {
                    samples.append(sample(from: last))
                }
                samples.append(sample(from: location, speedMps: movingSpeed))
            }

            lastAcceptedLocation = location
        }
    }

    private func sample(from location: CLLocation, speedMps: Double? = nil) -> GPSSample {
        let timestamp = startDate.addingTimeInterval(tracker.activeDuration(at: location.timestamp))
        return GPSSample(
            timestamp: timestamp,
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            speedMps: speedMps ?? max(0, location.speed),
            altitude: location.verticalAccuracy >= 0 ? location.altitude : nil
        )
    }

    private func startHeartRatePolling() {
        heartRateTask?.cancel()
        heartRateTask = Task { [weak self] in
            guard let self else { return }
            guard health.isAvailable else {
                heartRateState = .unavailable
                return
            }

            heartRateState = .requestingAuthorization
            guard await health.requestReadAuthorization() else {
                heartRateState = .unavailable
                return
            }

            if latestHeartRate == nil { heartRateState = .waitingForData }
            while !Task.isCancelled {
                let now = Date()
                let sessionSamples = await health.heartRateSamples(from: startDate, to: now)

                if !sessionSamples.isEmpty {
                    let latest = sessionSamples[sessionSamples.count - 1]
                    applyHeartRate(
                        WatchHeartRate(bpm: latest.bpm, measuredAt: latest.timestamp),
                        at: now
                    )
                    averageHeartRate = sessionSamples.reduce(0) { $0 + $1.bpm } / Double(sessionSamples.count)
                } else if let latest = await health
                    .heartRateSamples(from: now.addingTimeInterval(-30 * 60), to: now).last {
                    applyHeartRate(
                        WatchHeartRate(bpm: latest.bpm, measuredAt: latest.timestamp),
                        at: now
                    )
                } else if latestHeartRate == nil {
                    heartRateState = .waitingForData
                }
                try? await Task.sleep(for: .seconds(10))
            }
        }
    }

    /// 合并两个心率来源（手表实时推送 / HealthKit 轮询），按**测量时间**取更新的一条——
    /// 后到的不一定更新。够新才算实时，旧了如实标成「最近心率」，太旧就不显示，不推算。
    private func applyHeartRate(_ reading: WatchHeartRate?, at now: Date) {
        guard let merged = WatchHeartRate.fresher(latestHeartRate, reading) else { return }
        latestHeartRate = merged
        switch merged.freshness(at: now) {
        case .live:
            currentHeartRate = merged.bpm
            heartRateState = .live(merged.bpm)
        case .recent:
            currentHeartRate = merged.bpm
            heartRateState = .recent(merged.bpm)
        case .stale:
            currentHeartRate = nil
            heartRateState = .waitingForData
        }
    }
}

private struct ManualRideView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var session = ManualRideSession()
    @State private var now = Date()
    @State private var showingStopConfirmation = false
    @State private var showingDiscardConfirmation = false
    @State private var showingTooShortAlert = false
    @State private var showDashboard = false
    @AppStorage("overspeedAlertKmh") private var overspeedAlertKmh: Double = 0

    let onSave: (Ride) -> Void

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            ZStack {
                FreshHomeBackground()
                    .ignoresSafeArea()

                VStack(spacing: 14) {
                    if showDashboard {
                        dashboardPanel
                    } else {
                        mapPanel
                        metricGrid
                    }
                    controlPanel
                }
                .padding(16)
            }
            .navigationTitle(showDashboard ? Text("码表") : Text("骑行中"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") {
                        showingDiscardConfirmation = true
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        withAnimation { showDashboard.toggle() }
                    } label: {
                        Label(showDashboard ? String(localized: "地图") : String(localized: "码表"),
                              systemImage: showDashboard ? "map" : "gauge.with.needle")
                    }
                }
            }
            .onAppear {
                session.start()
                UIApplication.shared.isIdleTimerDisabled = true   // 骑行中屏幕常亮
            }
            .onDisappear {
                UIApplication.shared.isIdleTimerDisabled = false
            }
            .onReceive(timer) { date in
                now = date
                session.tick()
            }
            .confirmationDialog("结束这次骑行？", isPresented: $showingStopConfirmation, titleVisibility: .visible) {
                Button("结束并保存", role: .destructive) {
                    finishRide()
                }
                Button("继续骑行", role: .cancel) {}
            }
            .confirmationDialog("放弃这次骑行？", isPresented: $showingDiscardConfirmation, titleVisibility: .visible) {
                Button("放弃", role: .destructive) {
                    session.discard()
                    dismiss()
                }
                Button("继续骑行", role: .cancel) {}
            }
            .alert("骑行时间太短", isPresented: $showingTooShortAlert) {
                Button("知道了", role: .cancel) {}
            } message: {
                Text("少于 2 分钟的运动不会保存。")
            }
        }
    }

    private var mapPanel: some View {
        ZStack(alignment: .bottomLeading) {
            Map(position: .constant(mapPosition)) {
                if session.coordinates.count >= 2 {
                    MapPolyline(coordinates: session.coordinates)
                        .stroke(Color(red: 0.04, green: 0.62, blue: 0.82), lineWidth: 5)
                }
                if let first = session.coordinates.first {
                    Marker("起点", systemImage: "flag.fill", coordinate: first)
                        .tint(.green)
                }
                if let last = session.coordinates.last {
                    Annotation("当前位置", coordinate: last) {
                        Image(systemName: "location.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(Color(red: 0.04, green: 0.62, blue: 0.82))
                            .clipShape(Circle())
                    }
                }
            }
            .mapControls {
                MapUserLocationButton()
            }

            if session.isPaused {
                Color.white.opacity(0.22)
                    .allowsHitTesting(false)
                Image(systemName: "pause.fill")
                    .font(.system(size: 44, weight: .black))
                    .foregroundStyle(.white)
                    .frame(width: 86, height: 86)
                    .background(Color.black.opacity(0.34))
                    .clipShape(Circle())
                    .allowsHitTesting(false)
            }

            HStack(spacing: 8) {
                Label(routeStatusText, systemImage: "location.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color(red: 0.06, green: 0.36, blue: 0.42))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.white.opacity(0.84))
                    .clipShape(Capsule())
            }
            .padding(12)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 360)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.9), lineWidth: 1)
        )
        .shadow(color: Color(red: 0.20, green: 0.70, blue: 0.80).opacity(0.16), radius: 18, y: 10)
    }

    private var metricGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            liveMetric("时长", Formatters.durationClock(session.duration), "timer", .cyan)
            liveMetric("距离", Formatters.distance(session.distanceMeters), "point.topleft.down.curvedto.point.bottomright.up", .mint)
            liveMetric("均速", speedText, "speedometer", .orange)
            liveMetric(heartRateTitle, heartRateText, "heart.fill", .pink)
        }
    }

    /// 码表面板：当前时速大字 + 时长/距离/均速/心率。超速时时速变红。
    private var dashboardPanel: some View {
        let speedKmh = session.currentSpeedKmh
        let overspeeding = overspeedAlertKmh > 0 && speedKmh >= overspeedAlertKmh
        return VStack(spacing: 14) {
            Spacer(minLength: 0)

            VStack(spacing: 2) {
                Text(String(format: "%.1f", speedKmh))
                    .font(.system(size: 104, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .foregroundStyle(overspeeding ? Color.red : Color(red: 0.05, green: 0.42, blue: 0.50))
                    .contentTransition(.numericText())
                Text(overspeeding ? String(localized: "超速！注意安全") : String(localized: "公里/时"))
                    .font(.headline.weight(.bold))
                    .foregroundStyle(overspeeding ? .red : .secondary)
            }

            if session.isAutoPaused || session.isPaused {
                Label(session.isPaused ? String(localized: "已暂停") : String(localized: "停等中，计时暂停"),
                      systemImage: "pause.circle.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Color.orange.opacity(0.13))
                    .clipShape(Capsule())
            }

            Spacer(minLength: 0)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                liveMetric("时长", Formatters.durationClock(session.duration), "timer", .cyan)
                liveMetric("距离", Formatters.distance(session.distanceMeters), "point.topleft.down.curvedto.point.bottomright.up", .mint)
                liveMetric("均速", speedText, "speedometer", .orange)
                liveMetric(heartRateTitle, heartRateText, "heart.fill", .pink)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 8)
    }

    private var controlPanel: some View {
        HStack(spacing: 10) {
            Button {
                if session.isPaused {
                    session.resume()
                } else {
                    session.pause()
                }
            } label: {
                Label(session.isPaused ? String(localized: "继续") : String(localized: "暂停"), systemImage: session.isPaused ? "play.fill" : "pause.fill")
                    .font(.headline.weight(.heavy))
                    .foregroundStyle(Color(red: 0.06, green: 0.36, blue: 0.42))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.white.opacity(0.84))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.white.opacity(0.92), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)

            Button {
                showingStopConfirmation = true
            } label: {
                Label("结束骑行", systemImage: "stop.fill")
                    .font(.headline.weight(.heavy))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        LinearGradient(
                            colors: [
                                Color(red: 0.04, green: 0.68, blue: 0.82),
                                Color(red: 0.22, green: 0.82, blue: 0.60)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 2)
    }

    private var heartRateText: String {
        session.heartRateState.displayText
    }

    private var heartRateTitle: String {
        session.heartRateState.title
    }

    private var speedText: String {
        session.distanceMeters > 0 ? Formatters.speed(session.averageSpeedMps) : "0.0 公里/时"
    }

    private var routeStatusText: String {
        if session.isPaused { return String(localized: "已暂停") }
        if session.isAutoPaused { return String(localized: "停等中，移动后继续计时") }
        if session.currentCoordinate == nil { return String(localized: "等待定位") }
        if session.isRecordingRoute { return String(localized: "正在记录路线") }
        return String(localized: "定位中，移动后记录")
    }

    private var mapPosition: MapCameraPosition {
        guard let region = region(for: session.coordinates) else {
            return .automatic
        }
        return .region(region)
    }

    private func liveMetric(_ title: String, _ value: String, _ icon: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.caption.weight(.bold))
                .foregroundStyle(color)
                .frame(width: 24, height: 24)
                .background(color.opacity(0.13))
                .clipShape(Circle())
            Text(value)
                .font(.title3.weight(.heavy))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.white.opacity(0.82))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.88), lineWidth: 1)
        )
    }

    private func finishRide() {
        if let ride = session.stop() {
            onSave(ride)
            dismiss()
        } else {
            showingTooShortAlert = true
        }
    }

    private func region(for coords: [CLLocationCoordinate2D]) -> MKCoordinateRegion? {
        guard !coords.isEmpty else { return nil }
        let lats = coords.map(\.latitude)
        let lons = coords.map(\.longitude)
        let minLat = lats.min()!, maxLat = lats.max()!
        let minLon = lons.min()!, maxLon = lons.max()!
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
        let span = MKCoordinateSpan(
            latitudeDelta: max(0.004, (maxLat - minLat) * 1.7),
            longitudeDelta: max(0.004, (maxLon - minLon) * 1.7)
        )
        return MKCoordinateRegion(center: center, span: span)
    }
}
