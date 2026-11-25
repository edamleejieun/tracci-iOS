import Foundation
import Observation
import PhotosUI
import SwiftUI
import TracciNetworking

@Observable
@MainActor
final class EditProfileViewModel {
    private let authService: AuthService
    private let fileUploadService: FileUploadService

    // MARK: - Existing Fields

    var nickname: String
    private(set) var avatarUrl: String?
    private(set) var avatarFileId: String?
    private(set) var localAvatarImage: UIImage?
    private(set) var isSaving = false
    private(set) var isUploadingAvatar = false
    var errorMessage: String?
    var saveSuccess = false
    var validationError: String?

    // MARK: - Personal Fields (local-only until backend supports)

    enum Gender: String, Codable, CaseIterable {
        case male = "MALE"
        case female = "FEMALE"
        case undisclosed = "UNDISCLOSED"

        var displayName: String {
            switch self {
            case .male: return "男"
            case .female: return "女"
            case .undisclosed: return "保密"
            }
        }

        static let allCases: [Gender] = [.male, .female, .undisclosed]
    }

    var gender: Gender = .undisclosed
    var birthDate: Date? = nil
    var signature: String = ""

    // MARK: - Init

    init(user: User, authService: AuthService, fileUploadService: FileUploadService) {
        self.nickname = user.nickname ?? ""
        self.avatarUrl = user.avatarUrl
        self.avatarFileId = user.avatarFileId
        self.authService = authService
        self.fileUploadService = fileUploadService

        self.gender = Gender(rawValue: user.gender ?? "") ?? .undisclosed
        self.birthDate = Self.parseBirthDate(user.birthDate)
        self.signature = user.signature ?? ""
    }

    // MARK: - Validation

    var isSaveEnabled: Bool {
        let trimmed = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= 50 && !isSaving && !isUploadingAvatar
    }

    // MARK: - Avatar

    func processAvatarItem(_ item: PhotosPickerItem) async {
        isUploadingAvatar = true
        errorMessage = nil
        defer { isUploadingAvatar = false }

        do {
            let processed = try await ImagePickerProcessing.process(item: item, fileNamePrefix: "avatar")

            if let uiImage = UIImage(data: processed.data) {
                localAvatarImage = uiImage
            }

            let response = try await fileUploadService.uploadImage(
                businessType: "AVATAR",
                businessId: nil,
                imageData: processed.data,
                fileName: processed.fileName,
                contentType: processed.contentType,
                width: processed.width,
                height: processed.height
            )
            avatarFileId = response.id
        } catch {
            errorMessage = "头像上传失败：\(error.localizedDescription)"
            localAvatarImage = nil
        }
    }

    // MARK: - Save

    func save(into authSession: AuthSession) async {
        let trimmed = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            validationError = "昵称不能为空"
            return
        }
        guard trimmed.count <= 50 else {
            validationError = "昵称不能超过 50 个字符"
            return
        }
        guard !isSaving else { return }

        isSaving = true
        errorMessage = nil
        validationError = nil
        defer { isSaving = false }

        do {
            let updatedUser = try await authService.updateProfile(
                nickname: trimmed,
                avatarFileId: avatarFileId,
                signature: signature.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : String(signature.prefix(100)),
                gender: gender == .undisclosed ? nil : gender.rawValue,
                birthDate: birthDateString
            )
            authSession.restoreUser(updatedUser)
            saveSuccess = true
        } catch {
            errorMessage = "保存失败：\(error.localizedDescription)"
        }
    }

    // MARK: - Helpers

    private var birthDateString: String? {
        guard let date = birthDate else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: date)
    }

    static func parseBirthDate(_ string: String?) -> Date? {
        guard let string = string else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "yyyy-MM"
        guard let date = formatter.date(from: string) else { return nil }
        return date
    }
}
