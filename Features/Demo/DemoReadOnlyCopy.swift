import Foundation

/// Shared user-facing copy for Demo Journey read-only surfaces.
enum DemoReadOnlyCopy {
    /// Compact identity chip on home card and detail chrome.
    static let identityPill = "示例 · 只读"
    /// Longer banner line when space allows.
    static let banner = "示例旅程 · 仅供查看"
    static let toast = "示例旅程仅供查看"
    static let memoryUnavailable = "示例回忆暂不可用"
    static let exportUnavailable = "示例中不能导出或分享"
    static let shareUnavailable = "示例中不能分享"
    static let inviteUnavailable = "示例中不能邀请成员"
    static let activityEntry = "协作动态示例"
    static let activityReadOnly = "示例动态仅供查看"
    static let membersReadOnly = "示例成员仅供查看"
    static let membersInviteUnavailable = "示例中不能邀请成员"
    static let settlementReadOnly = "示例 AA 结算仅供查看"
    static let homeValueLine = "看看行程、日志和开支长什么样"
    static let homeAccessibilityLabelPrefix = "示例旅程，只读"
    static let homeAccessibilityHint = "打开后可浏览示例内容，不能编辑"

    // MARK: - P2 product-tour chrome

    /// First-visit soft coach under the demo stage rail.
    static let softCoach = "可切换上方阶段，浏览行程、日志和开支。示例仅供查看。"
    static let softCoachDismiss = "知道了"
    static let softCoachAccessibilityHint = "关闭后不再显示"

    /// Compact exit conversion in demo detail chrome (not sticky over feed).
    static let createOwnTrip = "创建我的旅程"
    static let createOwnTripAccessibilityHint = "退出示例并打开创建旅程"

    /// Ending page of demo memory story — no save/share.
    static let memoryBrowseOnly = "示例回顾仅供浏览，不能保存或分享"
}
