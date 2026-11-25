import Foundation

// MARK: - Update Profile

struct UpdateProfileRequest: Encodable {
    let nickname: String?
    let avatarFileId: String?
    let signature: String?
    let gender: String?
    let birthDate: String?
}

// MARK: - Send Verification Code

struct SendVerificationCodeResponse: Codable {
    let expireSeconds: Int
    let retryAfterSeconds: Int
}

struct SendVerificationCodeRequest: Encodable {
    let email: String
}

struct SendPhoneCodeRequest: Encodable {
    let phone: String
}

struct EmailBindConfirmRequest: Encodable {
    let email: String
    let code: String
    let password: String
}

struct VerifyPhoneCodeRequest: Encodable {
    let phone: String
    let code: String
}

// MARK: - Password Reset

struct PasswordResetConfirmRequest: Encodable {
    let email: String
    let code: String
    let newPassword: String
}

// MARK: - Change Password

struct ChangePasswordRequest: Encodable {
    let oldPassword: String
    let newPassword: String
}

// MARK: - Delete Account

struct DeleteAccountRequest: Encodable {
    let confirmText: String
    let reason: String?
    let password: String?
}

// MARK: - Account Security

struct AccountSecurityStatus: Codable, Equatable {
    let email: String?
    let phone: String?
    let phoneVerified: Bool?
    let hasPassword: Bool
    let bindings: AccountSecurityBindings?
}

struct AccountSecurityBindings: Codable, Equatable {
    let email: Bool?
    let phone: Bool?
    let wechat: Bool?
    let apple: Bool?
}

// MARK: - Feedback

struct FeedbackOption: Codable, Identifiable {
    let value: String
    let label: String

    var id: String { value }
}

struct FeedbackOptionsResponse: Codable {
    let types: [FeedbackOption]
    let statuses: [FeedbackOption]
    let contactTypes: [FeedbackOption]
    let platforms: [FeedbackOption]
}

struct FeedbackSubmitRequest: Encodable {
    let type: String
    let title: String?
    let content: String
    let contactType: String?
    let contact: String?
    let imageIds: [String]?
    let platform: String
    let appVersion: String?
    let systemInfo: FeedbackSystemInfo?
}

struct FeedbackSystemInfo: Encodable {
    let brand: String
    let model: String
    let system: String
}

struct FeedbackSubmitResponse: Codable {
    let id: String
    let status: String
    let createdAt: String
}

// MARK: - FAQ Item

struct FAQItem: Identifiable {
    let id = UUID()
    let question: String
    let answer: String
}

struct FAQCategory: Identifiable {
    let id = UUID()
    let title: String
    let icon: String
    let items: [FAQItem]
}

enum FAQData {
    static let categories: [FAQCategory] = [
        FAQCategory(
            title: "旅程相关",
            icon: "map",
            items: [
                FAQItem(
                    question: "如何创建新旅程？",
                    answer: "在首页点击底部导航栏中间的「+」按钮，选择手动新建即可创建新旅程。填写旅程名称、目的地和日期后即可开始记录。"
                ),
                FAQItem(
                    question: "如何编辑已有的旅程？",
                    answer: "进入旅程详情页，点击右上角的编辑按钮即可修改旅程信息，包括名称、目的地、日期和封面图片。"
                ),
                FAQItem(
                    question: "可以删除旅程吗？",
                    answer: "可以。在旅程详情页点击右上角菜单，选择删除旅程。删除后该旅程下的所有行程节点、日记和费用记录也会被删除，请谨慎操作。"
                ),
            ]
        ),
        FAQCategory(
            title: "费用与导出",
            icon: "chart.bar",
            items: [
                FAQItem(
                    question: "如何记录旅行费用？",
                    answer: "进入旅程详情页，切换到「费用」标签页，点击添加按钮即可记录每笔费用。支持选择费用类型、金额和备注。"
                ),
                FAQItem(
                    question: "如何导出旅行回忆？",
                    answer: "在「回忆」页面选择要导出的旅程，选择喜欢的模板即可生成旅行回忆卡片，支持保存到相册或分享给好友。"
                ),
            ]
        ),
        FAQCategory(
            title: "账号与安全",
            icon: "person",
            items: [
                FAQItem(
                    question: "如何修改密码？",
                    answer: "进入「我的」→「账号安全」→「修改密码」，输入原密码和新密码即可修改。修改密码后需要重新登录。"
                ),
                FAQItem(
                    question: "如何联系客服？",
                    answer: "你可以通过「帮助与反馈」页面提交反馈，或发送邮件至 support@tracci.cn 联系我们。"
                ),
            ]
        ),
    ]
}
