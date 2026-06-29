import SwiftUI
import StoreKit
import SwiftData

/// 订阅页 — 价格/货币由 StoreKit 按用户 Storefront 动态返回，不硬编码金额。
/// 沿用 ai-cleaner 同款结构：hero + 功能清单 + 年/月套餐卡 + 购买/恢复/试用/隐私条款。
/// 字号一律 ≥ .footnote（Apple 审核 2.3.2 对 paywall 小字会拒；不用 caption/caption2）。
struct PaywallView: View {
    @StateObject private var manager = SubscriptionManager.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var selectedPlan: SubscriptionManager.ProductID = .yearly
    @State private var isPurchasing = false
    @State private var showError = false
    @State private var showSuccess = false
    @State private var rideCount = 0
    @State private var totalKm = 0.0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    heroSection.padding(.bottom, 28)
                    featuresSection.padding(.horizontal, 24)
                    planSection.padding(.top, 24)
                    purchaseSection
                        .padding(.top, 24).padding(.horizontal, 24).padding(.bottom, 40)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("恢复购买") { Task { await manager.restore() } }
                        .font(.footnote).foregroundStyle(.secondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary).font(.title3)
                    }
                }
            }
            .alert("提示", isPresented: $showError) {
                Button("确定", role: .cancel) {}
            } message: {
                Text(manager.errorMessage ?? "购买失败，请稍后重试")
            }
            .alert("订阅成功", isPresented: $showSuccess) {
                Button("好的") { dismiss() }
            } message: {
                Text("Pro 已激活，全部功能已解锁")
            }
        }
        .task {
            if manager.products.isEmpty { await manager.loadProducts() }
            loadRideStats()
        }
    }

    // MARK: - Hero

    private var heroSection: some View {
        ZStack {
            LinearGradient(
                colors: [Color.accentColor, Color.accentColor.opacity(0.7)],
                startPoint: .topLeading, endPoint: .bottomTrailing)

            VStack(spacing: 14) {
                Image(systemName: "bicycle")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(.white)
                VStack(spacing: 8) {
                    Text("解锁 轻骑运动 Pro")
                        .font(.title2.bold()).foregroundStyle(.white)
                    Text("小众安静风景路线 + 逐向语音导航，骑得更尽兴")
                        .font(.subheadline).foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                }
                if rideCount > 0 {
                    HStack(spacing: 24) {
                        PaywallStatBadge(value: "\(rideCount)", label: "次骑行")
                        PaywallStatBadge(value: String(format: "%.0f", totalKm), label: "公里里程")
                    }
                    .padding(.top, 4)
                }
            }
            .padding(.top, 36).padding(.bottom, 32).padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity)
        .clipShape(UnevenRoundedRectangle(
            bottomLeadingRadius: 24, bottomTrailingRadius: 24, style: .continuous))
    }

    // MARK: - Features

    private var featuresSection: some View {
        VStack(spacing: 10) {
            ProFeatureRow(icon: "leaf.fill",                 color: .green,  text: "小众安静 · 风景骑行路线推荐")
            ProFeatureRow(icon: "location.north.line.fill",  color: .blue,   text: "逐向语音导航 + 自动偏航重算")
            ProFeatureRow(icon: "arrow.triangle.capsulepath", color: .orange, text: "环线推荐 · 5/10/20km 一键成圈")
            ProFeatureRow(icon: "chart.bar.fill",            color: .purple, text: "高级统计 · 周趋势与里程图表")
            ProFeatureRow(icon: "lock.shield.fill",          color: .teal,   text: "全程本地处理 · 隐私零上传")
        }
    }

    // MARK: - Plans

    private var planSection: some View {
        VStack(spacing: 12) {
            let yearlyTrialText: String = {
                if let offer = manager.yearlyProduct?.subscription?.introductoryOffer,
                   offer.paymentMode == .freeTrial {
                    return "试用 \(trialPeriodText(for: offer))，到期自动续费"
                }
                return manager.yearlyPerMonthDisplay.map { "折合每月约 \($0)" } ?? "年付更划算"
            }()

            PlanCard(
                title: "按年订阅", price: manager.yearlyProduct?.displayPrice ?? "—", period: "/ 年",
                badge: manager.yearlySavingsPercent.map { "省 \($0)%" },
                subtext: yearlyTrialText, isSelected: selectedPlan == .yearly, isRecommended: true
            ) { selectedPlan = .yearly }
            .redacted(reason: manager.yearlyProduct == nil ? .placeholder : [])

            let monthlyTrialText: String = {
                if let offer = manager.monthlyProduct?.subscription?.introductoryOffer,
                   offer.paymentMode == .freeTrial {
                    return "试用 \(trialPeriodText(for: offer))，到期自动续费"
                }
                return "按月续订随时取消"
            }()

            PlanCard(
                title: "按月订阅", price: manager.monthlyProduct?.displayPrice ?? "—", period: "/ 月",
                badge: nil, subtext: monthlyTrialText,
                isSelected: selectedPlan == .monthly, isRecommended: false
            ) { selectedPlan = .monthly }
            .redacted(reason: manager.monthlyProduct == nil ? .placeholder : [])

            if manager.products.isEmpty, !manager.isLoading {
                Button { Task { await manager.loadProducts() } } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                        Text("重试加载价格")
                    }
                    .font(.footnote).foregroundStyle(Color.accentColor)
                }
                .padding(.top, 4)
            }
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Purchase

    private var selectedProduct: Product? {
        selectedPlan == .yearly ? manager.yearlyProduct : manager.monthlyProduct
    }

    private func trialPeriodText(for offer: Product.SubscriptionOffer) -> String {
        let v = offer.period.value
        switch offer.period.unit {
        case .day: return "\(v) 天"
        case .week: return "\(v) 周"
        case .month: return "\(v) 个月"
        case .year: return "\(v) 年"
        @unknown default: return "\(v) 天"
        }
    }

    private var purchaseSection: some View {
        VStack(spacing: 14) {
            Text("订阅自动续费，可随时在系统设置中取消")
                .font(.footnote).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button { Task { await doPurchase() } } label: {
                ZStack {
                    if isPurchasing {
                        ProgressView().tint(.white)
                    } else {
                        let hasTrial = selectedProduct?.subscription?.introductoryOffer?.paymentMode == .freeTrial
                        Text(hasTrial ? "开始免费试用" : "立即订阅")
                            .font(.headline).foregroundStyle(.white)
                    }
                }
                .frame(maxWidth: .infinity).padding(.vertical, 16)
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14))
            }
            .disabled(isPurchasing || manager.isLoading || selectedProduct == nil)

            HStack(spacing: 20) {
                Link("隐私政策", destination: URL(string: "https://docs.qq.com/space/DS2ZFcGNVZmVob0RN")!)
                Link("服务条款", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
            }
            .font(.footnote).foregroundStyle(Color.accentColor)
        }
    }

    private func doPurchase() async {
        guard let product = selectedProduct else {
            manager.errorMessage = "产品信息未加载，请稍后重试"; showError = true; return
        }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            if try await manager.purchase(product) { showSuccess = true }
        } catch {
            manager.errorMessage = error.localizedDescription; showError = true
        }
    }

    private func loadRideStats() {
        let store = RideStore(context: modelContext)
        guard let rides = try? store.allRides() else { return }
        rideCount = rides.count
        totalKm = rides.compactMap(\.distanceMeters).reduce(0, +) / 1000
    }
}

// MARK: - Sub-components

private struct PaywallStatBadge: View {
    let value: String
    let label: String
    var body: some View {
        VStack(spacing: 4) {
            Text(value).font(.title3.bold().monospacedDigit()).foregroundStyle(.white)
            Text(label).font(.footnote).foregroundStyle(.white.opacity(0.8))
        }
    }
}

private struct ProFeatureRow: View {
    let icon: String
    let color: Color
    let text: String
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 16)).foregroundStyle(color).frame(width: 28)
            Text(text).font(.subheadline)
            Spacer()
            Image(systemName: "checkmark").font(.footnote.bold()).foregroundStyle(.green)
        }
    }
}

private struct PlanCard: View {
    let title: String
    let price: String
    let period: String
    let badge: String?
    let subtext: String
    let isSelected: Bool
    let isRecommended: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .strokeBorder(isSelected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 2)
                        .frame(width: 22, height: 22)
                    if isSelected {
                        Circle().fill(Color.accentColor).frame(width: 12, height: 12)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.subheadline.weight(.medium)).lineLimit(1)
                    if isRecommended {
                        Text("推荐")
                            .font(.footnote.bold()).foregroundStyle(.white)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color.accentColor, in: Capsule())
                    }
                    Text(subtext).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                }

                Spacer(minLength: 4)

                VStack(alignment: .trailing, spacing: 2) {
                    HStack(alignment: .lastTextBaseline, spacing: 2) {
                        Text(price).font(.title3.bold()).foregroundStyle(isSelected ? Color.accentColor : .primary)
                        Text(period).font(.footnote).foregroundStyle(.secondary)
                    }
                    .fixedSize()
                    if let badge {
                        Text(badge)
                            .font(.footnote.bold()).foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.orange, in: Capsule())
                    }
                }
                .layoutPriority(1)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2))
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}
