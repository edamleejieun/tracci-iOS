import Foundation
import Observation
import UIKit

@Observable
@MainActor
final class HelpFeedbackViewModel {
    private let profileService: ProfileService

    // FAQ state
    var expandedFAQ: UUID?
    let faqCategories = FAQData.categories

    // Feedback form state
    var feedbackTypes: [FeedbackOption] = []
    var contactTypes: [FeedbackOption] = []
    var selectedType: String = "BUG"
    var title: String = ""
    var content: String = ""
    var selectedContactType: String = "EMAIL"
    var contact: String = ""

    private(set) var isLoadingOptions = false
    private(set) var isSubmitting = false
    var submitSuccess = false
    var errorMessage: String?
    var optionsWarning: String?

    init(profileService: ProfileService) {
        self.profileService = profileService
    }

    var isSubmitEnabled: Bool {
        !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && contentCharacterCount <= 1000
            && !isSubmitting
    }

    var contentCharacterCount: Int {
        content.count
    }

    func loadOptions() async {
        guard !isLoadingOptions else { return }
        isLoadingOptions = true
        optionsWarning = nil
        defer { isLoadingOptions = false }

        do {
            let options = try await profileService.getFeedbackOptions()
            feedbackTypes = options.types
            contactTypes = Self.emailOnlyContactTypes(from: options.contactTypes)
            if let firstType = options.types.first {
                selectedType = firstType.value
            }
            selectedContactType = "EMAIL"
        } catch {
            optionsWarning = "反馈选项暂时无法更新，已使用默认选项。"
            // Use default values if options fail to load
            if feedbackTypes.isEmpty {
                feedbackTypes = [
                    FeedbackOption(value: "BUG", label: "Bug 反馈"),
                    FeedbackOption(value: "FEATURE", label: "功能建议"),
                    FeedbackOption(value: "UX", label: "体验问题"),
                    FeedbackOption(value: "ACCOUNT", label: "账号问题"),
                    FeedbackOption(value: "OTHER", label: "其他"),
                ]
            }
            if contactTypes.isEmpty {
                contactTypes = [Self.defaultEmailContactType]
            }
            selectedContactType = "EMAIL"
        }
    }

    func submit() async {
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty else {
            errorMessage = "请输入反馈内容"
            return
        }
        guard trimmedContent.count <= 1000 else {
            errorMessage = "反馈内容不能超过 1000 个字符"
            return
        }

        guard !isSubmitting else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedContact = contact.trimmingCharacters(in: .whitespacesAndNewlines)

        let systemInfo = FeedbackSystemInfo(
            brand: "Apple",
            model: UIDevice.current.model,
            system: "iOS \(UIDevice.current.systemVersion)"
        )

        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String

        do {
            _ = try await profileService.submitFeedback(
                type: selectedType,
                title: trimmedTitle.isEmpty ? nil : trimmedTitle,
                content: trimmedContent,
                contactType: trimmedContact.isEmpty ? nil : selectedContactType,
                contact: trimmedContact.isEmpty ? nil : trimmedContact,
                imageIds: nil,
                appVersion: appVersion,
                systemInfo: systemInfo
            )
            submitSuccess = true
            AppHaptics.success()
            title = ""
            content = ""
            contact = ""
        } catch {
            errorMessage = "提交失败：\(error.localizedDescription)"
        }
    }

    func resetForm() {
        title = ""
        content = ""
        contact = ""
        errorMessage = nil
        submitSuccess = false
        optionsWarning = nil
    }

    private static let defaultEmailContactType = FeedbackOption(value: "EMAIL", label: "邮箱")

    private static func emailOnlyContactTypes(from options: [FeedbackOption]) -> [FeedbackOption] {
        let emailOptions = options.filter { $0.value.uppercased() == "EMAIL" }
        return emailOptions.isEmpty ? [defaultEmailContactType] : emailOptions
    }
}
