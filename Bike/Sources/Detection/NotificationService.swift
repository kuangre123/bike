import Foundation
import SwiftData
import UserNotifications
import CyclingDomain

/// 本地通知：被动检测到运动后推「已记录一次X · 撤销」，撤销动作删除该记录（乐观添加+可撤销）。
@MainActor
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    nonisolated private static let undoActionID = "UNDO_WORKOUT"
    nonisolated private static let categoryID = "WORKOUT_DETECTED"
    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
        super.init()
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let undo = UNNotificationAction(identifier: Self.undoActionID, title: "撤销", options: [.destructive])
        let category = UNNotificationCategory(identifier: Self.categoryID, actions: [undo], intentIdentifiers: [], options: [])
        center.setNotificationCategories([category])
    }

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func notifyWorkoutAdded(rideID: UUID, activityType: ActivityType, duration: TimeInterval) {
        let content = UNMutableNotificationContent()
        content.title = "已记录一次\(Formatters.activityLabel(activityType))"
        content.body = "\(Formatters.duration(duration)) · 滑动通知可撤销"
        content.categoryIdentifier = Self.categoryID
        content.userInfo = ["rideID": rideID.uuidString]
        let request = UNNotificationRequest(identifier: rideID.uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let actionID = response.actionIdentifier
        let idString = response.notification.request.content.userInfo["rideID"] as? String
        if actionID == Self.undoActionID, let idString, let id = UUID(uuidString: idString) {
            Task { @MainActor [weak self, id] in
                self?.deleteRide(id: id)
            }
        }
        completionHandler()
    }

    private func deleteRide(id: UUID) {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<RideModel>(predicate: #Predicate { $0.rideID == id })
        if let model = try? context.fetch(descriptor).first {
            context.delete(model)
            try? context.save()
        }
    }
}
