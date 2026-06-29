import StoreKit
import Foundation

/// 订阅管理器 — 基于 StoreKit 2。价格/货币由 StoreKit 按用户 Storefront 返回，代码不硬编码金额。
/// 移植自 ai-cleaner 的同款实现，去掉照片专属配额逻辑，只保留 Pro 解锁。
@MainActor
final class SubscriptionManager: ObservableObject {

    static let shared = SubscriptionManager()

    /// App Store Connect / .storekit 中配置的产品 ID（必须三处逐字节一致）。
    enum ProductID: String, CaseIterable {
        case monthly = "com.bochen.bike.subscription.monthly"
        case yearly  = "com.bochen.bike.subscription.yearly"
    }

    @Published var products: [Product] = []
    @Published var purchasedProductIDs: Set<String> = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    /// 订阅状态首次校验完成。冷启动时 currentEntitlements 是异步的，UI 在该值变 true 前
    /// 不应根据 isPro 做"自动弹订阅页"这类决策，否则已订阅用户每次冷启动会看到 paywall 闪现。
    @Published var entitlementsLoaded: Bool = false

    var isPro: Bool { !purchasedProductIDs.isEmpty }

    var monthlyProduct: Product? { products.first { $0.id == ProductID.monthly.rawValue } }
    var yearlyProduct: Product? { products.first { $0.id == ProductID.yearly.rawValue } }

    // MARK: - 动态价格（不硬编码）

    /// 年付折合每月（与年付同币种格式）。例：年付 ¥88 → "¥7.33"。
    var yearlyPerMonthDisplay: String? {
        guard let yearly = yearlyProduct else { return nil }
        let perMonth = yearly.price / Decimal(12)
        return perMonth.formatted(yearly.priceFormatStyle)
    }

    /// 年付相比按月 12 个月节省的百分比；月付缺失或年付不划算时返回 nil。
    var yearlySavingsPercent: Int? {
        guard let monthly = monthlyProduct, let yearly = yearlyProduct else { return nil }
        let yearTotal = monthly.price * Decimal(12)
        guard yearTotal > yearly.price else { return nil }
        let savings = yearTotal - yearly.price
        let ratio = NSDecimalNumber(decimal: savings / yearTotal).doubleValue
        let pct = Int((ratio * 100).rounded())
        return pct > 0 ? pct : nil
    }

    private var transactionListener: Task<Void, Error>?

    private init() {
        transactionListener = listenForTransactions()
        Task { await loadProducts() }
        Task { await updatePurchasedProducts() }
    }

    deinit { transactionListener?.cancel() }

    // MARK: - Load

    func loadProducts() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let ids = ProductID.allCases.map(\.rawValue)
            let fetched = try await Product.products(for: ids)
                .sorted { a, _ in a.id == ProductID.monthly.rawValue }  // 月在前、年在后
            products = fetched
            errorMessage = fetched.isEmpty ? NSLocalizedString("产品信息未加载，请稍后重试", comment: "") : nil
        } catch {
            errorMessage = NSLocalizedString("加载产品信息失败", comment: "") + "：\(error.localizedDescription)"
        }
    }

    // MARK: - Purchase

    func purchase(_ product: Product) async throws -> Bool {
        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            // 交易已在 App Store 生效；verified/unverified 都按成功处理，由 updatePurchasedProducts 兜底。
            let transaction: Transaction
            switch verification {
            case .verified(let t), .unverified(let t, _): transaction = t
            }
            await updatePurchasedProducts()
            await transaction.finish()
            return true
        case .userCancelled, .pending:
            return false
        @unknown default:
            return false
        }
    }

    // MARK: - Restore

    func restore() async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await AppStore.sync()
            await updatePurchasedProducts()
        } catch {
            errorMessage = NSLocalizedString("恢复购买失败", comment: "") + "：\(error.localizedDescription)"
        }
    }

    // MARK: - Entitlements

    func updatePurchasedProducts() async {
        var purchased: Set<String> = []

        // 1) currentEntitlements — 主来源。客户端门槛只做 UX 展示，verified/unverified 都算。
        for await result in Transaction.currentEntitlements {
            let transaction: Transaction
            switch result {
            case .verified(let t), .unverified(let t, _): transaction = t
            }
            if transaction.revocationDate == nil { purchased.insert(transaction.productID) }
        }

        // 2) 兜底：subscription.status —— currentEntitlements 在测试环境抖动返回空时也能识别。
        for product in products where !purchased.contains(product.id) {
            guard let subscription = product.subscription else { continue }
            if let statuses = try? await subscription.status, let status = statuses.first {
                switch status.state {
                case .subscribed, .inGracePeriod, .inBillingRetryPeriod: purchased.insert(product.id)
                default: break
                }
            }
        }

        purchasedProductIDs = purchased
        if !entitlementsLoaded { entitlementsLoaded = true }
    }

    // MARK: - Listener

    private func listenForTransactions() -> Task<Void, Error> {
        Task.detached {
            for await result in Transaction.updates {
                guard let transaction = try? self.checkVerified(result) else { continue }
                await self.updatePurchasedProducts()
                await transaction.finish()
            }
        }
    }

    private nonisolated func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified: throw SubscriptionError.verificationFailed
        case .verified(let value): return value
        }
    }

    enum SubscriptionError: Error, LocalizedError {
        case verificationFailed
        var errorDescription: String? {
            switch self {
            case .verificationFailed: return NSLocalizedString("交易验证失败", comment: "")
            }
        }
    }
}
