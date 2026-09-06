import Foundation
import CyclingDomain

/// 「从 Apple 健康导入哪些第三方来源」的用户偏好，以及已被用户删掉的导入记录（墓碑）。
///
/// 默认一个都不勾：把别人 app 的数据搬进来是用户的决定，不替他做主。
enum ExternalSourcePreferences {
    static let enabledKey = "externalSourceIDs"
    static let dismissedKey = "dismissedExternalWorkoutIDs"

    static var enabledSourceIDs: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: enabledKey) ?? []) }
        set { UserDefaults.standard.set(newValue.sorted(), forKey: enabledKey) }
    }

    static func isEnabled(_ sourceID: String) -> Bool {
        enabledSourceIDs.contains(sourceID)
    }

    static func setEnabled(_ enabled: Bool, for sourceID: String) {
        var ids = enabledSourceIDs
        if enabled { ids.insert(sourceID) } else { ids.remove(sourceID) }
        enabledSourceIDs = ids
    }

    /// 用户主动删掉的导入记录。没有墓碑的话，下次导入又会把它搬回来。
    static var dismissedWorkoutIDs: [UUID] {
        get {
            (UserDefaults.standard.stringArray(forKey: dismissedKey) ?? [])
                .compactMap(UUID.init(uuidString:))
        }
        set { UserDefaults.standard.set(newValue.map(\.uuidString), forKey: dismissedKey) }
    }

    /// 记下「这条别再导进来了」。列表有上限，超出丢最早的。
    static func dismiss(_ workoutID: UUID) {
        dismissedWorkoutIDs = ExternalWorkoutImport.appendingDismissed(dismissedWorkoutIDs, workoutID)
    }
}
