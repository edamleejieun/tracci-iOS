import Foundation

/// 旅程能力快照变更（如所有权转让）的进程内广播。
/// 详情/编辑页在导航栈下层时用于立即替换本地 `TripAccessContext`。
enum TripAccessUpdate {
    static let notification = Notification.Name("tracci.tripAccessDidUpdate")

    private static let tripIdKey = "tripId"
    private static let accessKey = "access"

    static func post(tripId: String, access: TripAccessContext) {
        NotificationCenter.default.post(
            name: notification,
            object: nil,
            userInfo: [
                tripIdKey: tripId,
                accessKey: access
            ]
        )
    }

    static func tripId(from notification: Notification) -> String? {
        notification.userInfo?[tripIdKey] as? String
    }

    static func access(from notification: Notification) -> TripAccessContext? {
        notification.userInfo?[accessKey] as? TripAccessContext
    }
}
